#!/usr/bin/env python3
"""Check that the package allowlist excludes private, cached or credential data.

This is a packaging gate, not a secret scanner. It inspects the paths declared in
build.zig.zon (or an archive) and fails when a forbidden directory or filename
would ship. Run from the repository root:

    python tools/check_package.py
    python tools/check_package.py --archive path/to/package.tar.gz
    python tools/check_package.py --self-test
"""
from __future__ import annotations

import argparse
import pathlib
import re
import tarfile
import tempfile
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

FORBIDDEN_PARTS = {
    ".git",
    ".private",
    ".local",
    ".zig-cache",
    ".zig-cache-local",
    ".turbo",
    "zig-out",
    "node_modules",
    "coverage",
    "test-results",
    ".claude",
    ".cursor",
    ".agents",
    "__pycache__",
}

FORBIDDEN_FILES = re.compile(
    r"(^\.env($|\.)|^id_(rsa|ed25519)($|\.)|\.(pem|key|p12|pfx)$|^credentials($|\.)|^secrets($|\.))",
    re.IGNORECASE,
)

REQUIRED = {"build.zig", "build.zig.zon", "LICENSE", "NOTICE", "README.md"}


def read_paths(zon: pathlib.Path) -> list[str]:
    text = zon.read_text(encoding="utf-8")
    match = re.search(r"\.paths\s*=\s*\.\{(.*?)\}", text, re.DOTALL)
    if not match:
        raise ValueError("build.zig.zon has no .paths allowlist")
    paths = re.findall(r'"([^"]+)"', match.group(1))
    if not paths:
        raise ValueError("package allowlist is empty")
    for entry in paths:
        p = pathlib.PurePosixPath(entry)
        if p.is_absolute() or ".." in p.parts or entry in ("", "."):
            raise ValueError(f"invalid allowlist entry: {entry!r}")
    return paths


def check_names(names: list[str], required: set[str] = REQUIRED) -> list[str]:
    errors: list[str] = []
    for name in names:
        parts = pathlib.PurePosixPath(name).parts
        for part in parts:
            if part in FORBIDDEN_PARTS:
                errors.append(f"forbidden directory in package: {name}")
                break
        if FORBIDDEN_FILES.search(pathlib.PurePosixPath(name).name):
            errors.append(f"forbidden credential/cache file in package: {name}")
    present = set(names)
    for item in sorted(required):
        if item not in present:
            errors.append(f"required package file missing: {item}")
    return errors


def collect_from_paths(root: pathlib.Path, paths: list[str]) -> list[str]:
    names: list[str] = []
    for entry in paths:
        target = root / entry
        if not target.exists():
            raise ValueError(f"allowlisted path does not exist: {entry}")
        if target.is_dir():
            for child in sorted(target.rglob("*")):
                if child.is_file():
                    names.append(child.relative_to(root).as_posix())
        else:
            names.append(entry)
    return names


def check_source(root: pathlib.Path) -> tuple[list[str], int]:
    paths = read_paths(root / "build.zig.zon")
    names = collect_from_paths(root, paths)
    return check_names(names), len(names)


def check_archive(path: pathlib.Path) -> tuple[list[str], int]:
    with tarfile.open(path) as tar:
        members = [m.name for m in tar.getmembers() if m.isfile()]
    if not members:
        return ["archive contains no files"], 0
    prefixes = {name.split("/", 1)[0] for name in members}
    strip = len(prefixes) == 1 and all("/" in name for name in members)
    names = [name.split("/", 1)[1] if strip else name for name in members]
    return check_names(names), len(names)


def self_test() -> int:
    failures: list[str] = []
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        (root / "src").mkdir()
        (root / "build.zig").write_text("// build\n")
        (root / "build.zig.zon").write_text(
            '.{ .paths = .{ "build.zig", "build.zig.zon", "src", "LICENSE", "NOTICE", "README.md" } }\n'
        )
        (root / "src" / "ok.zig").write_text("// ok\n")
        for name in ("LICENSE", "NOTICE", "README.md"):
            (root / name).write_text("fixture\n")

        errors, _ = check_source(root)
        if errors:
            failures.append(f"clean fixture failed: {errors}")

        (root / "src" / ".env").write_text("TOKEN=secret\n")
        errors, _ = check_source(root)
        if not any(".env" in error for error in errors):
            failures.append("injected .env was not rejected")
        (root / "src" / ".env").unlink()

        (root / "src" / "key.pem").write_text("not a real key\n")
        errors, _ = check_source(root)
        if not any("key.pem" in error for error in errors):
            failures.append("injected key.pem was not rejected")
        (root / "src" / "key.pem").unlink()

        archive = root / "package.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(root / "build.zig", arcname="pkg/build.zig")
            tar.add(root / "build.zig.zon", arcname="pkg/build.zig.zon")
            tar.add(root / "src" / "ok.zig", arcname="pkg/src/ok.zig")
            for name in ("LICENSE", "NOTICE", "README.md"):
                tar.add(root / name, arcname=f"pkg/{name}")
        errors, _ = check_archive(archive)
        if errors:
            failures.append(f"clean archive failed: {errors}")

        (root / "src" / ".env").write_text("TOKEN=secret\n")
        (root / ".private").mkdir()
        (root / ".private" / "plan.md").write_text("private plan\n")
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(root / "build.zig", arcname="pkg/build.zig")
            tar.add(root / "build.zig.zon", arcname="pkg/build.zig.zon")
            tar.add(root / "src" / "ok.zig", arcname="pkg/src/ok.zig")
            tar.add(root / "src" / ".env", arcname="pkg/src/.env")
            tar.add(root / ".private" / "plan.md", arcname="pkg/.private/plan.md")
            for name in ("LICENSE", "NOTICE", "README.md"):
                tar.add(root / name, arcname=f"pkg/{name}")
        errors, _ = check_archive(archive)
        if not any(".env" in error for error in errors):
            failures.append("archive with .env was not rejected")
        if not any(".private" in error for error in errors):
            failures.append("archive with .private was not rejected")

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")
        return 1
    print("PASS: package checker self-test")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=pathlib.Path, default=ROOT)
    parser.add_argument("--archive", type=pathlib.Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    try:
        if args.archive:
            errors, count = check_archive(args.archive)
            label = str(args.archive)
        else:
            errors, count = check_source(args.source)
            label = str(args.source)
    except (OSError, ValueError, tarfile.TarError) as exc:
        print(f"FAIL: {exc}")
        return 1

    if errors:
        for error in errors:
            print(f"FAIL: {error}")
        return 1

    print(f"PASS: {count} package files checked in {label}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
