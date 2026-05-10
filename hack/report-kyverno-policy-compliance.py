#!/usr/bin/env python3
"""Generate a Kyverno ClusterPolicy compliance matrix report."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from kyverno_utils import iter_kyverno_policies


def value(annotations: dict[str, Any], *keys: str) -> str:
    for key in keys:
        raw = annotations.get(key, "")
        if str(raw).strip():
            return str(raw).strip()
    return "MISSING"


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    policy_root = repo_root / "platform" / "infrastructure"
    out_path = repo_root / "docs" / "operations" / "kyverno-policy-compliance-matrix.md"

    rows: list[tuple[str, str, str, str, str, str]] = []
    for file_path, doc in iter_kyverno_policies(policy_root):
        metadata = doc.get("metadata", {}) or {}
        spec = doc.get("spec", {}) or {}
        annotations = metadata.get("annotations", {}) or {}

        name = str(metadata.get("name", "<unknown>"))
        title = value(annotations, "policies.kyverno.io/title")
        severity = value(annotations, "policies.kyverno.io/severity", "cryptophys.io/severity")
        description = value(
            annotations,
            "policies.kyverno.io/description",
            "cryptophys.io/description",
        )
        vfa = str(spec.get("validationFailureAction", "MISSING"))
        background = spec.get("background", "MISSING")
        rows.append(
            (
                name,
                str(file_path.relative_to(repo_root)),
                title,
                severity,
                description,
                f"{vfa} / {background}",
            )
        )

    lines: list[str] = []
    lines.append("# Kyverno Policy Compliance Matrix")
    lines.append("")
    lines.append(
        f"Generated at: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S %Z')}"
    )
    lines.append("")
    lines.append(
        "This report is generated from `platform/infrastructure/**/*.yaml` for Kyverno `ClusterPolicy` objects."
    )
    lines.append("")
    lines.append("| Policy | File | Title | Severity | Description | Behavior (`validationFailureAction / background`) |")
    lines.append("|---|---|---|---|---|---|")

    for name, relpath, title, severity, description, behavior in rows:
        safe_description = description.replace("\n", " ").replace("|", "\\|")
        lines.append(
            f"| `{name}` | `{relpath}` | {title} | {severity} | {safe_description} | {behavior} |"
        )

    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
