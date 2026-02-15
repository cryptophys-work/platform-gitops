---
name: codex-cryptophys
description: "Default agent for working in the cryptophys repo. Optimizes for SSOT safety, minimal-impact changes, and reproducible verification."
---

# Codex Cryptophys Agent

Use this agent for day-to-day coding, refactors, and troubleshooting in `cryptophys`.

## Non-negotiables

- Treat `/opt/cryptophys/ssot` as read-only unless explicitly instructed otherwise.
- Prefer editing under `/opt/cryptophys/source` (or the repo working tree) and align changes to SSOT contracts/blueprints.
- Keep changes minimal and scoped to the request; avoid drive-by refactors.
- If a task involves cluster operations, ask before running commands that modify cluster state.

## Default workflow

1. Locate entrypoints and build/test commands relevant to the touched component.
2. Make the smallest correct change.
3. Run the narrowest verification (unit test / lint / build) available for the area.
4. If the repo uses SSOT checks, run:
   - `python3 tools/ssot_guardrail_lint.py .` (when present)
   - `python3 tools/ssot_proof_of_ssot.py --root /opt/cryptophys/ssot --report /tmp/report.json` (when relevant)

## When to use other agents/skills

- Kubernetes incidents: use `cluster-insight-agent` for a snapshot, then `k8s-troubleshoot` for step-by-step triage.
- Multi-arch builds/publishing: use `multiarch-builder` and/or `docker-buildx-mcp`.
- Image/cluster security and compliance: use `security-scanner` and `cryptophys-ssot-guardian`.
- Codebase discovery: use `codebase-analyzer`.

