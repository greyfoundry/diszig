#!/usr/bin/env python3
"""Validate the public coverage manifest and sanitized fixture conventions.

Coverage is evidence, not a claim. An implemented surface must cite a real
symbol file, a real test file containing a test block, and documentation. A
live-verified surface must include dated authorization evidence. Fixture data
must not contain credentials or private user data.

    python tools/check_coverage.py
    python tools/check_coverage.py --self-test
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import re
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "coverage" / "coverage.json"
FIXTURES = ROOT / "tests" / "fixtures"

STATUSES = {"implemented", "partial", "planned", "gated", "external", "deprecated"}
SCOPED = {"gated", "external", "deprecated"}

TOKEN_PATTERNS = [
    re.compile(r"Authorization:\s*(Bot|Bearer)\s+[A-Za-z0-9._-]{12,}", re.IGNORECASE),
    re.compile(r"\b[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]{20,}\b"),
    re.compile(r"-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    re.compile(r"\bmfa\.[A-Za-z0-9_-]{20,}\b"),
]
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})")
ALLOWED_EMAIL_DOMAINS = {"example.com", "example.invalid", "example.org"}


def check_fixture_file(path: pathlib.Path) -> list[str]:
    if path.suffix.lower() not in {".json", ".txt", ".csv", ".yaml", ".yml", ".bin"}:
        return []
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return [f"fixture is not UTF-8 text: {path}"]
    errors = []
    for pattern in TOKEN_PATTERNS:
        if pattern.search(text):
            errors.append(f"credential-like value in fixture: {path}")
            break
    for match in EMAIL.finditer(text):
        if match.group(1).lower() not in ALLOWED_EMAIL_DOMAINS:
            errors.append(f"non-synthetic email in fixture: {path}")
            break
    return errors


def check_fixtures(root: pathlib.Path) -> list[str]:
    fixture_root = root / "tests" / "fixtures"
    if not fixture_root.is_dir():
        return []
    errors = []
    for path in sorted(fixture_root.rglob("*")):
        if path.is_file() and path.name != "README.md":
            errors.extend(check_fixture_file(path))
    return errors


def check_manifest(data: dict, root: pathlib.Path) -> list[str]:
    errors: list[str] = []
    if data.get("schema") != 1:
        errors.append("coverage schema must be 1")
    surfaces = data.get("surfaces")
    if not isinstance(surfaces, list):
        return errors + ["coverage.surfaces must be a list"]

    seen: set[str] = set()
    for index, surface in enumerate(surfaces):
        label = surface.get("id") or f"surface[{index}]"
        if not surface.get("id"):
            errors.append(f"{label}: missing id")
        if label in seen:
            errors.append(f"{label}: duplicate id")
        seen.add(label)

        status = surface.get("status")
        if status not in STATUSES:
            errors.append(f"{label}: invalid status {status!r}")
            continue

        if not surface.get("source"):
            errors.append(f"{label}: missing source")

        if status in SCOPED:
            if not surface.get("reason"):
                errors.append(f"{label}: {status} requires a reason")
            continue

        if status == "planned":
            continue

        if not (surface.get("typed") or surface.get("raw")):
            errors.append(f"{label}: implemented/partial must be typed or raw")

        symbols = surface.get("symbols") or []
        tests = surface.get("tests") or []
        docs = surface.get("docs") or []
        if not symbols:
            errors.append(f"{label}: missing symbol evidence")
        if not tests:
            errors.append(f"{label}: missing test evidence")
        if not docs:
            errors.append(f"{label}: missing documentation evidence")

        for path_text in symbols + docs:
            if not (root / path_text).is_file():
                errors.append(f"{label}: evidence file missing: {path_text}")
        for path_text in tests:
            path = root / path_text
            if not path.is_file():
                errors.append(f"{label}: test file missing: {path_text}")
                continue
            text = path.read_text(encoding="utf-8")
            if not re.search(r'^test\s*(?:"|\{)', text, re.MULTILINE):
                errors.append(f"{label}: test file has no test block: {path_text}")

        if surface.get("live_verified"):
            evidence = surface.get("live_evidence")
            if not isinstance(evidence, dict):
                errors.append(f"{label}: live_verified requires live_evidence")
            else:
                for key in ("date", "authorization", "artifact", "result"):
                    if not evidence.get(key):
                        errors.append(f"{label}: live_evidence missing {key}")
                try:
                    day = dt.date.fromisoformat(str(evidence.get("date")))
                    if day > dt.date.today():
                        errors.append(f"{label}: live evidence date is in the future")
                except ValueError:
                    errors.append(f"{label}: live evidence date must be YYYY-MM-DD")

    return errors


def self_test() -> int:
    failures = []
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        (root / "src").mkdir()
        (root / "src" / "ok.zig").write_text('test "ok" {}\n')
        (root / "docs").mkdir()
        (root / "docs" / "ok.mdx").write_text("# ok\n")

        clean = {
            "schema": 1,
            "surfaces": [{
                "id": "ok",
                "kind": "primitive",
                "status": "implemented",
                "typed": True,
                "symbols": ["src/ok.zig"],
                "tests": ["src/ok.zig"],
                "docs": ["docs/ok.mdx"],
                "source": "fixture",
                "live_verified": False,
            }],
        }
        if check_manifest(clean, root):
            failures.append("clean manifest failed")

        missing_symbol = json.loads(json.dumps(clean))
        missing_symbol["surfaces"][0]["symbols"] = ["src/missing.zig"]
        if not check_manifest(missing_symbol, root):
            failures.append("missing symbol was not rejected")

        no_test = json.loads(json.dumps(clean))
        (root / "src" / "empty.zig").write_text("pub const x = 1;\n")
        no_test["surfaces"][0]["symbols"] = ["src/empty.zig"]
        no_test["surfaces"][0]["tests"] = ["src/empty.zig"]
        if not check_manifest(no_test, root):
            failures.append("test file without a test block was not rejected")

        live = json.loads(json.dumps(clean))
        live["surfaces"][0]["live_verified"] = True
        if not check_manifest(live, root):
            failures.append("live_verified without evidence was not rejected")

        fixtures = root / "tests" / "fixtures"
        fixtures.mkdir(parents=True)
        (fixtures / "leak.json").write_text(
            '{"authorization":"Bot MTA1234567890123456789012.ABCDEF.GHIJKLMNOPQRSTUVWXYZ123456"}\n'
        )
        if not check_fixtures(root):
            failures.append("credential fixture was not rejected")

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")
        return 1
    print("PASS: coverage checker self-test")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()

    try:
        data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"FAIL: cannot read coverage manifest: {exc}")
        return 1

    errors = check_manifest(data, ROOT) + check_fixtures(ROOT)
    if errors:
        for error in errors:
            print(f"FAIL: {error}")
        return 1
    print(f"PASS: {len(data['surfaces'])} coverage surfaces checked")
    return 0


if __name__ == "__main__":
    sys.exit(main())
