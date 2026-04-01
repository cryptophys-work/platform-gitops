#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Iterable


@dataclass
class Finding:
    category: str
    severity: str
    repo: str
    path: str
    line: int
    message: str


SECRET_REF_RE = re.compile(r"^\s*name:\s*([A-Za-z0-9._-]+)\s*$")
REMOTE_REF_KEY_RE = re.compile(r"^\s*key:\s*([A-Za-z0-9/_-]+)\s*$")
ENV_VALUE_RE = re.compile(r"^\s*value:\s*\"?([^\"]+)\"?\s*$")

TRACKED_SECRETS = {
    "apps-gitops-repo-headless",
    "apps-gitops-repo-internal",
    "aide-gitea-auth",
    "gitea-git-credentials",
    "github-creds",
    "nexus-gitea-build-creds",
    "openclaw-secrets",
    "tekton-gitea-basic-auth",
}

MACHINE_SECRET_NAMES = {
    "apps-gitops-repo-headless",
    "apps-gitops-repo-internal",
    "aide-gitea-auth",
    "gitea-git-credentials",
    "nexus-gitea-build-creds",
    "openclaw-secrets",
    "tekton-gitea-basic-auth",
}

ADMIN_MACHINE_PATHS = {
    "apps/gitea/admin",
}


def iter_files(root: Path) -> Iterable[Path]:
    for pattern in ("**/*.yaml", "**/*.yml", "**/*.sh"):
        yield from root.glob(pattern)


def load_text(path: Path) -> list[str]:
    try:
        return path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return path.read_text(encoding="latin-1").splitlines()


def index_declared_secrets(root: Path) -> dict[str, list[str]]:
    declared: dict[str, list[str]] = {}
    for path in iter_files(root):
        lines = load_text(path)
        kind = None
        for line in lines:
            stripped = line.strip()
            if stripped.startswith("kind:"):
                kind = stripped.split(":", 1)[1].strip()
                break
        if kind not in {"ExternalSecret", "Secret"}:
            continue
        for line in lines:
            stripped = line.strip()
            if stripped.startswith("name:"):
                value = stripped.split(":", 1)[1].strip().strip('"')
                if value in TRACKED_SECRETS:
                    declared.setdefault(value, []).append(str(path))
    return declared


def audit_repo(repo_name: str, root: Path, declared: dict[str, list[str]]) -> list[Finding]:
    findings: list[Finding] = []

    for path in iter_files(root):
        rel = str(path.relative_to(root))
        lines = load_text(path)

        current_secret: str | None = None
        current_env: str | None = None
        expect_secret_ref_name = False

        for idx, line in enumerate(lines, start=1):
            secret_match = SECRET_REF_RE.match(line)
            if secret_match:
                candidate = secret_match.group(1)
                if expect_secret_ref_name and candidate in TRACKED_SECRETS:
                    if candidate not in declared or not declared.get(candidate):
                        findings.append(
                            Finding(
                                category="undeclared-secret-owner",
                                severity="high",
                                repo=repo_name,
                                path=rel,
                                line=idx,
                                message=(
                                    f"Secret reference '{candidate}' has no Secret/ExternalSecret manifest "
                                    "in the audited repos."
                                ),
                            )
                        )
                    expect_secret_ref_name = False
                if candidate in TRACKED_SECRETS:
                    current_secret = candidate

            if line.strip().startswith("- name:"):
                current_env = line.split(":", 1)[1].strip()

            remote_ref_match = REMOTE_REF_KEY_RE.match(line)
            if remote_ref_match and current_secret in MACHINE_SECRET_NAMES:
                remote_key = remote_ref_match.group(1)
                if remote_key in ADMIN_MACHINE_PATHS:
                    findings.append(
                        Finding(
                            category="admin-password-source",
                            severity="high",
                            repo=repo_name,
                            path=rel,
                            line=idx,
                            message=(
                                f"Machine secret '{current_secret}' still sources '{remote_key}', "
                                "which is an interactive admin credential path."
                            ),
                        )
                    )

            if current_env == "GITEA_USER":
                env_value_match = ENV_VALUE_RE.match(line)
                if env_value_match and env_value_match.group(1) == "gitea-admin":
                    findings.append(
                        Finding(
                            category="hardcoded-admin-user",
                            severity="medium",
                            repo=repo_name,
                            path=rel,
                            line=idx,
                            message="Automation workload hardcodes GITEA_USER=gitea-admin.",
                        )
                    )

            if line.strip() in {"secretKeyRef:", "secret:"}:
                expect_secret_ref_name = True

            if "secretName:" in line:
                ref_name = line.split(":", 1)[1].strip().strip('"')
                if ref_name in TRACKED_SECRETS and ref_name not in declared:
                    findings.append(
                        Finding(
                            category="undeclared-secret-owner",
                            severity="high",
                            repo=repo_name,
                            path=rel,
                            line=idx,
                            message=(
                                f"Secret reference '{ref_name}' has no Secret/ExternalSecret manifest "
                                "in the audited repos."
                            ),
                        )
                    )
                elif ref_name in TRACKED_SECRETS and not declared.get(ref_name):
                    findings.append(
                        Finding(
                            category="undeclared-secret-owner",
                            severity="high",
                            repo=repo_name,
                            path=rel,
                            line=idx,
                            message=(
                                f"Secret reference '{ref_name}' has no Secret/ExternalSecret manifest "
                                "in the audited repos."
                            ),
                        )
                    )

    return dedupe(findings)


def dedupe(findings: list[Finding]) -> list[Finding]:
    seen: set[tuple[str, str, str, int, str]] = set()
    out: list[Finding] = []
    for finding in findings:
        key = (
            finding.category,
            finding.repo,
            finding.path,
            finding.line,
            finding.message,
        )
        if key not in seen:
            seen.add(key)
            out.append(finding)
    return out


def summarize(findings: list[Finding]) -> dict[str, object]:
    categories: dict[str, int] = {}
    severities: dict[str, int] = {}
    for finding in findings:
        categories[finding.category] = categories.get(finding.category, 0) + 1
        severities[finding.severity] = severities.get(finding.severity, 0) + 1
    return {
        "total_findings": len(findings),
        "by_category": categories,
        "by_severity": severities,
    }


def print_human(findings: list[Finding]) -> None:
    if not findings:
        print("No automation secret anti-patterns detected.")
        return

    for finding in findings:
        print(
            f"[{finding.severity}] {finding.category} "
            f"{finding.repo}:{finding.path}:{finding.line} - {finding.message}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Audit automation secret anti-patterns across cryptophys repos."
    )
    parser.add_argument("--apps-root", type=Path, required=True)
    parser.add_argument("--platform-root", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--format", choices=("human", "json"), default="human")
    parser.add_argument("--fail-on-findings", action="store_true")
    args = parser.parse_args()

    declared: dict[str, list[str]] = {}
    declared.update(index_declared_secrets(args.apps_root))
    for name, paths in index_declared_secrets(args.platform_root).items():
        declared.setdefault(name, []).extend(paths)

    findings = []
    findings.extend(audit_repo("apps-gitops", args.apps_root, declared))
    findings.extend(audit_repo("platform-gitops", args.platform_root, declared))
    findings = sorted(findings, key=lambda f: (f.severity, f.repo, f.path, f.line))

    payload = {
        "summary": summarize(findings),
        "declared_secrets": {k: sorted(v) for k, v in sorted(declared.items()) if k in TRACKED_SECRETS},
        "findings": [asdict(f) for f in findings],
    }

    if args.output:
        args.output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    if args.format == "json":
        json.dump(payload, sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        print_human(findings)
        print()
        print(json.dumps(payload["summary"], indent=2))

    return 1 if args.fail_on_findings and findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
