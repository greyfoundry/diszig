#!/usr/bin/env python3
"""Fetch and verify the pinned official libdave release artifact.

The archives are Discord's own release assets for v1.3.0 (C++ build,
BoringSSL backend). Each asset is pinned by SHA-256; a mismatch is a hard
failure and nothing is extracted.

    python tools/fetch_libdave.py
    python tools/fetch_libdave.py --platform linux-x64
    python tools/fetch_libdave.py --check-only

Extracted layout: third_party/libdave/v1.3.0/<platform>/{include,lib,bin,licenses}
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import shutil
import sys
import urllib.request
import zipfile

VERSION = "1.3.0"
TAG = "v1.3.0/cpp"
BASE = f"https://github.com/discord/libdave/releases/download/{TAG}"

ASSETS = {
    "windows-x64": (
        "libdave-Windows-X64-boringssl.zip",
        "82993c4a9e5836f1dca01b4f7afeba72454321034dc41fda74bc239f620be6a2",
    ),
    "linux-x64": (
        "libdave-Linux-X64-boringssl.zip",
        "096e2b4cb64f4c9a5551b954ff717a89db7c5fe94e901860c339dd98d6f2c15d",
    ),
    "linux-arm64": (
        "libdave-Linux-ARM64-boringssl.zip",
        "024bb556da335c884471256bcb30e4871e19b0a63aaaf9eec9898f83d8e5f81c",
    ),
    "macos-x64": (
        "libdave-macOS-X64-boringssl.zip",
        "041140b9fe4059e777d512219f796d00c8a3e38e98eb14cd49c9c5804b64367a",
    ),
    "macos-arm64": (
        "libdave-macOS-ARM64-boringssl.zip",
        "111e46c61f2fa7ef23c7a2f7840330e59bcdb75e77728d2244536a031e601e02",
    ),
}


def detect_platform() -> str:
    import platform

    system = platform.system().lower()
    machine = platform.machine().lower()
    if system == "windows" and machine in {"amd64", "x86_64"}:
        return "windows-x64"
    if system == "linux" and machine in {"amd64", "x86_64"}:
        return "linux-x64"
    if system == "linux" and machine in {"aarch64", "arm64"}:
        return "linux-arm64"
    if system == "darwin" and machine in {"x86_64", "amd64"}:
        return "macos-x64"
    if system == "darwin" and machine in {"arm64", "aarch64"}:
        return "macos-arm64"
    raise SystemExit(f"unsupported platform for libdave {TAG}: {system}/{machine}")


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_extract(archive: pathlib.Path, destination: pathlib.Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    root = destination.resolve()
    with zipfile.ZipFile(archive) as bundle:
        for member in bundle.infolist():
            target = (destination / member.filename).resolve()
            if not str(target).startswith(str(root)):
                raise SystemExit(f"refusing zip path traversal: {member.filename}")
            if member.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with bundle.open(member) as source, target.open("wb") as sink:
                shutil.copyfileobj(source, sink)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", default=None, help="windows-x64, linux-x64, linux-arm64, macos-x64, macos-arm64")
    parser.add_argument("--check-only", action="store_true", help="download and verify without extracting")
    parser.add_argument("--keep", action="store_true", help="keep the downloaded archive")
    args = parser.parse_args()

    platform = args.platform or detect_platform()
    if platform not in ASSETS:
        raise SystemExit(f"unknown platform {platform!r}; choose from {', '.join(ASSETS)}")
    name, expected = ASSETS[platform]

    root = pathlib.Path(__file__).resolve().parent.parent
    download_dir = root / ".local" / "cache" / "libdave"
    download_dir.mkdir(parents=True, exist_ok=True)
    archive = download_dir / name

    if not archive.exists():
        print(f"downloading {BASE}/{name}")
        with urllib.request.urlopen(f"{BASE}/{name}", timeout=120) as response:
            archive.write_bytes(response.read())

    actual = sha256(archive)
    if actual != expected:
        raise SystemExit(f"hash mismatch for {name}: expected {expected}, got {actual}")
    print(f"verified {name} sha256={actual}")

    if args.check_only:
        return 0

    destination = root / "third_party" / "libdave" / f"v{VERSION}" / platform
    safe_extract(archive, destination)
    if not args.keep:
        archive.unlink()
    print(f"extracted to {destination.relative_to(root)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
