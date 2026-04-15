#!/usr/bin/env python3
"""Enforce minimum metadata annotations on Kyverno ClusterPolicies."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

import yaml


REQUIRED_TITLE = ("policies.kyverno.io/title",)
REQUIRED_SEVERITY_ANY = ("policies.kyverno.io/severity", "cryptophys.io/severity")
REQUIRED_DESCRIPTION_ANY = ("policies.kyverno.io/description", "cryptophys.io/description")


def load_docs(path: Path) -> list[dict[str, Any]]:
    docs: list[dict[str, Any]] = []
    for doc in yaml.safe_load_all(path.read_text(encoding="utf-8")):
        if isinstance(doc, dict):
            docs.append(doc)
    return docs


def main() -> int:
    root = Path(__file__).resolve().parent.parent / "platform" / "infrastructure"
    findings: list[str] = []

    for file_path in sorted(root.rglob("*.yaml")):
        for doc in load_docs(file_path):
            if doc.get("kind") != "ClusterPolicy":
                continue
            api_version = str(doc.get("apiVersion", ""))
            if not api_version.startswith("kyverno.io/"):
                continue

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
