from __future__ import annotations

from pathlib import Path
from typing import Any, Iterable

import yaml


def load_yaml_docs(path: Path) -> list[dict[str, Any]]:
    """Load all YAML documents from a file that are dictionaries."""
    docs: list[dict[str, Any]] = []
    try:
        content = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        content = path.read_text(encoding="latin-1")

    for doc in yaml.safe_load_all(content):
        if isinstance(doc, dict):
            docs.append(doc)
    return docs


def iter_kyverno_policies(policy_root: Path) -> Iterable[tuple[Path, dict[str, Any]]]:
    """Yield (path, doc) for all Kyverno ClusterPolicies under policy_root."""
    for file_path in sorted(policy_root.rglob("*.yaml")):
        for doc in load_yaml_docs(file_path):
            if doc.get("kind") == "ClusterPolicy" and str(doc.get("apiVersion", "")).startswith("kyverno.io/"):
                yield file_path, doc
