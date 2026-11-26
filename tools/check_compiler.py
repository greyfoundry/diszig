#!/usr/bin/env python3
"""Fail when the active compiler is outside the tested baseline.

The reviewed baseline is Zig 0.17.1. `--advisory` prints the version without
failing so a developer can evaluate a newer compiler without claiming support.
"""
from __future__ import annotations

import argparse
import subprocess
import sys

TESTED = "0.17.1"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--advisory", action="store_true")
    args = parser.parse_args()

    try:
        result = subprocess.run(
            ["zig", "version"], text=True, capture_output=True, check=True
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"FAIL: cannot run zig version: {exc}")
        return 2

    version = result.stdout.strip()
    print(f"zig version: {version} (tested baseline: {TESTED})")
    if version == TESTED:
        print("PASS: tested compiler")
        return 0
    if args.advisory:
        print("ADVISORY: compiler is not the tested baseline; no support claim is made")
        return 0

    print("FAIL: compiler differs from the tested baseline; migrate deliberately")
    return 1


if __name__ == "__main__":
    sys.exit(main())
