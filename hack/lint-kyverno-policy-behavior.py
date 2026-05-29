#!/usr/bin/env python3
"""Enforce explicit Kyverno ClusterPolicy behavior fields."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

import yaml


VALID_ACTIONS = {"audit", "enforce"}


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
            spec = doc.get("spec", {}) or {}

            if "validationFailureAction" not in spec:
                findings.append(f"{file_path}: policy={name} missing=spec.validationFailureAction")
            else:
                action = str(spec.get("validationFailureAction", "")).strip().lower()
                if action not in VALID_ACTIONS:
                    findings.append(
                        f"{file_path}: policy={name} invalid=spec.validationFailureAction({spec.get('validationFailureAction')})"
                    )

            if "background" not in spec:
                findings.append(f"{file_path}: policy={name} missing=spec.background")
            elif not isinstance(spec.get("background"), bool):
                findings.append(
                    f"{file_path}: policy={name} invalid=spec.background({type(spec.get('background')).__name__})"
                )

    if findings:
        print("error: kyverno ClusterPolicy behavior fields are incomplete/invalid", file=sys.stderr)
        for finding in findings:
            print(f" - {finding}", file=sys.stderr)
        return 1

    print("success: kyverno policy behavior fields are explicit and valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
