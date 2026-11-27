#!/usr/bin/env python3
"""Fetch and verify the pinned official Opus release source.

    python tools/fetch_opus.py
    python tools/fetch_opus.py --check-only

The archive is Xiph's release asset for v1.5.2, pinned by SHA-256. A mismatch is
a hard failure and nothing is extracted. Extraction goes to
third_party/opus/v1.5.2/src (gitignored by the native-artifact rule).
"""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import sys
import tarfile
import urllib.request

VERSION = "1.5.2"
URL = f"https://github.com/xiph/opus/releases/download/v{VERSION}/opus-{VERSION}.tar.gz"
SHA256 = "65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1"


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()

    root = pathlib.Path(__file__).resolve().parent.parent
    cache = root / ".local" / "cache" / "opus"
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / f"opus-{VERSION}.tar.gz"

    if not archive.exists():
        print(f"downloading {URL}")
        with urllib.request.urlopen(URL, timeout=180) as response:
            archive.write_bytes(response.read())

    actual = sha256(archive)
    if actual != SHA256:
        raise SystemExit(f"hash mismatch: expected {SHA256}, got {actual}")
    print(f"verified opus-{VERSION}.tar.gz sha256={actual}")
    if args.check_only:
        return 0

    destination = root / "third_party" / "opus" / f"v{VERSION}"
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as bundle:
        for member in bundle.getmembers():
            target = (destination / member.name).resolve()
            if not str(target).startswith(str(destination.resolve())):
                raise SystemExit(f"refusing tar path traversal: {member.name}")
        bundle.extractall(destination, filter="data")
    print(f"extracted to {destination.relative_to(root)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
