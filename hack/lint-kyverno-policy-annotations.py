#!/usr/bin/env python3
"""Enforce minimum metadata annotations on Kyverno ClusterPolicies."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

from kyverno_utils import iter_kyverno_policies


REQUIRED_TITLE = ("policies.kyverno.io/title",)
REQUIRED_SEVERITY_ANY = ("policies.kyverno.io/severity", "cryptophys.io/severity")
REQUIRED_DESCRIPTION_ANY = ("policies.kyverno.io/description", "cryptophys.io/description")


def main() -> int:
    root = Path(__file__).resolve().parent.parent / "platform" / "infrastructure"
    findings: list[str] = []

    for file_path, doc in iter_kyverno_policies(root):
        name = str(doc.get("metadata", {}).get("name", "<unknown>"))
        annotations = doc.get("metadata", {}).get("annotations", {}) or {}
        missing: list[str] = []
        if not any(str(annotations.get(k, "")).strip() for k in REQUIRED_TITLE):
            missing.append("policies.kyverno.io/title")
        if not any(str(annotations.get(k, "")).strip() for k in REQUIRED_SEVERITY_ANY):
            missing.append("policies.kyverno.io/severity|cryptophys.io/severity")
        if not any(str(annotations.get(k, "")).strip() for k in REQUIRED_DESCRIPTION_ANY):
            missing.append("policies.kyverno.io/description|cryptophys.io/description")
        if missing:
            findings.append(f"{file_path}: policy={name} missing={', '.join(missing)}")

    if findings:
        print("error: kyverno ClusterPolicy annotation requirements not met", file=sys.stderr)
        for finding in findings:
            print(f" - {finding}", file=sys.stderr)
        return 1

    print("success: kyverno policy annotations are complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
