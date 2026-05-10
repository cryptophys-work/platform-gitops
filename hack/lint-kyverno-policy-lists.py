#!/usr/bin/env python3
"""Detect duplicate scalar entries in Kyverno ClusterPolicy list fields."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

from kyverno_utils import load_yaml_docs


LIST_KEYS = {"values", "namespaces", "names"}
TARGET_KIND = "ClusterPolicy"
TARGET_API_PREFIX = "kyverno.io/"


def scan_node(node: Any, path: str, findings: list[str], file_path: Path, policy_name: str) -> None:
    if isinstance(node, dict):
        for key, value in node.items():
            next_path = f"{path}.{key}" if path else str(key)
            if key in LIST_KEYS and isinstance(value, list):
                scalars = [item for item in value if isinstance(item, str)]
                duplicates = sorted({item for item in scalars if scalars.count(item) > 1})
                if duplicates:
                    findings.append(
                        f"{file_path}: policy={policy_name} path={next_path} duplicates={', '.join(duplicates)}"
                    )
            scan_node(value, next_path, findings, file_path, policy_name)
    elif isinstance(node, list):
        for idx, item in enumerate(node):
            scan_node(item, f"{path}[{idx}]", findings, file_path, policy_name)


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    policy_root = root / "platform" / "infrastructure"
    findings: list[str] = []

    for file_path in sorted(policy_root.rglob("*.yaml")):
        docs = load_yaml_docs(file_path)
        for doc in docs:
            api_version = str(doc.get("apiVersion", ""))
            kind = str(doc.get("kind", ""))
            if not api_version.startswith(TARGET_API_PREFIX) or kind != TARGET_KIND:
                continue
            policy_name = str(doc.get("metadata", {}).get("name", "<unknown>"))
            scan_node(doc.get("spec", {}), "spec", findings, file_path, policy_name)

    if findings:
        print("error: duplicate entries found in Kyverno ClusterPolicy list fields", file=sys.stderr)
        for finding in findings:
            print(f" - {finding}", file=sys.stderr)
        return 1

    print("success: kyverno policy list values are unique")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
