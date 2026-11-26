#!/usr/bin/env python3
"""Read-only OpenAPI operation/model drift comparison.

Compares a reviewed baseline to a separately acquired candidate. It never
fetches, rewrites or updates a pin. Drift is reported for manual review and a
non-zero exit is returned; publication remains a human decision.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import sys
from typing import Any

METHODS = {"get", "put", "post", "delete", "options", "head", "patch", "trace"}


def digest(value: Any) -> str:
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    ).hexdigest()


def inventory(document: dict) -> dict:
    if not isinstance(document.get("paths"), dict):
        raise ValueError("schema has no paths object")
    operations = {}
    for path, item in document["paths"].items():
        if not isinstance(item, dict):
            continue
        for method, operation in item.items():
            if method not in METHODS or not isinstance(operation, dict):
                continue
            key = f"{method.upper()} {path}"
            operations[key] = digest({
                "operation": operation,
                "parameters": item.get("parameters", []),
            })
    models = {
        name: digest(value)
        for name, value in sorted(document.get("components", {}).get("schemas", {}).items())
    }
    return {"operations": operations, "models": models}


def compare(baseline: dict, current: dict, label: str) -> list[str]:
    before = inventory(baseline)
    after = inventory(current)
    findings: list[str] = []

    for key in sorted(before["operations"].keys() - after["operations"].keys()):
        findings.append(f"{label}: operation removed: {key}")
    for key in sorted(after["operations"].keys() - before["operations"].keys()):
        findings.append(f"{label}: operation added: {key}")
    for key in sorted(before["operations"].keys() & after["operations"].keys()):
        if before["operations"][key] != after["operations"][key]:
            findings.append(f"{label}: operation changed: {key}")

    for key in sorted(before["models"].keys() - after["models"].keys()):
        findings.append(f"{label}: model removed: {key}")
    for key in sorted(after["models"].keys() - before["models"].keys()):
        findings.append(f"{label}: model added: {key}")
    for key in sorted(before["models"].keys() & after["models"].keys()):
        if before["models"][key] != after["models"][key]:
            findings.append(f"{label}: model changed: {key}")
    return findings


def load(path: pathlib.Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read {path}: {exc}") from exc


def self_test() -> int:
    baseline = {
        "paths": {
            "/a": {"get": {"operationId": "a"}},
            "/gone": {"post": {"operationId": "gone"}},
        },
        "components": {"schemas": {"A": {"type": "string"}}},
    }
    current = {
        "paths": {
            "/a": {"get": {"operationId": "a", "description": "changed"}},
            "/new": {"post": {"operationId": "new"}},
        },
        "components": {"schemas": {"A": {"type": "string"}, "B": {"type": "integer"}}},
    }
    findings = compare(baseline, current, "standard")
    expected = [
        "operation removed: POST /gone",
        "operation added: POST /new",
        "operation changed: GET /a",
        "model added: B",
    ]
    missing = [text for text in expected if not any(text in finding for finding in findings)]
    if missing:
        for item in missing:
            print(f"FAIL: self-test did not detect {item}")
        return 1
    print("PASS: drift checker self-test")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=pathlib.Path)
    parser.add_argument("--current", type=pathlib.Path)
    parser.add_argument("--preview-baseline", type=pathlib.Path)
    parser.add_argument("--preview-current", type=pathlib.Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return self_test()
    if not args.baseline or not args.current:
        parser.error("--baseline and --current are required")

    try:
        findings = compare(load(args.baseline), load(args.current), "standard")
        if args.preview_baseline and args.preview_current:
            findings += compare(
                load(args.preview_baseline), load(args.preview_current), "preview"
            )
    except ValueError as exc:
        print(f"FAIL: {exc}")
        return 2

    if not findings:
        print("PASS: no schema drift detected")
        return 0
    for finding in findings:
        print(f"DRIFT: {finding}")
    print("Review required; no pin, plan or public claim was changed.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
