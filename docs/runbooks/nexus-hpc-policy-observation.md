# Nexus HPC Policy Observation Checklist

This runbook defines an observation cycle before changing any `nexus-hpc` placement validation from `Audit` to `Enforce`.

## Scope

- Policy: `validate-nexus-hpc-placement`
- Rule: `require-nexus-hpc-selector-or-required-affinity`
- Namespace selector: `cryptophys.io/node-class=nexus-hpc`

## Success Criteria

- No unexpected `fail` results for critical workloads in target namespaces.
- All intentional violations are triaged with owner + action + ETA.
- At least one complete observation window shows stable results.

## Observation Window

- Minimum duration: 24h across normal workload activity.
- Recommended: 48-72h if frequent rollouts are expected.
- Re-run window after any significant scheduling policy change.

## Target Namespaces (Priority Order)

1. `aide`
2. `cerebrum`
3. `cqls-compute`
4. `image-factory`
5. `tekton-system`
6. `trustedledger` (if pinned workloads are still expected on nexus-hpc lane)

## Triage Matrix

- **P0**: Ray head/worker, LLM inference path, build pipeline core workers.
- **P1**: Control APIs tied to model serving latency or high-memory runtime.
- **P2**: Supporting services that can tolerate delayed migration.

## Operational Checklist

- [ ] Confirm policy is still `Audit`:
  - `kubectl get cpol validate-nexus-hpc-placement -o yaml`
- [ ] Collect PolicyReports for target namespaces:
  - `kubectl get polr -A`
  - `kubectl get cpolr`
- [ ] Filter entries for `validate-nexus-hpc-placement` rule.
- [ ] Group all `fail` results by namespace/workload/owner/team.
- [ ] Classify each failure as:
  - expected temporary drift,
  - real misplacement bug,
  - false-positive pattern.
- [ ] Open remediation tasks for all real misplacements.
- [ ] Apply manifest fixes (nodeSelector or required nodeAffinity to `nexus-hpc`).
- [ ] Verify next report cycle no longer shows the same failure.
- [ ] Record final go/no-go decision for `Enforce`.

## Recommended Evidence Capture

Store these artifacts in your change ticket or PR:

- PolicyReport snapshots before remediation.
- Diff of workload manifests fixed during the window.
- PolicyReport snapshots after remediation.
- Final summary table:
  - namespace,
  - workload,
  - initial status,
  - final status,
  - owner.

## Triage Template (Markdown)

Use this table for each observation window:

| Namespace | Workload | Priority (P0/P1/P2) | Rule Result | Root Cause | Owner | Remediation | ETA | Retest Status |
|---|---|---|---|---|---|---|---|---|
| aide | rayservice-head | P0 | fail | missing `nodeSelector` | team-aide | add `cryptophys.io/node-class=nexus-hpc` | 2026-04-18 | pending |
| cerebrum | llm-worker | P0 | pass | n/a | team-cerebrum | n/a | n/a | pass |

Guidance:
- `Rule Result`: `pass` or `fail` from PolicyReport.
- `Root Cause`: keep concise and factual.
- `Retest Status`: `pending`, `pass`, or `fail`.

## Decision Log Template

Use one log entry per cycle:

| Window Start | Window End | P0 Open | P1 Open | P2 Open | Decision | Approved By | Notes |
|---|---|---|---|---|---|---|---|
| 2026-04-15 00:00 UTC | 2026-04-16 00:00 UTC | 0 | 1 | 2 | Keep Audit | platform-ops | P1 remediation in progress |

Decision values:
- `Keep Audit`
- `Ready for Enforce`

## Cutover Decision

Move `validate-nexus-hpc-placement` from `Audit` to `Enforce` only when:

- all P0 and P1 workloads are compliant, and
- remaining P2 exceptions are explicitly approved with expiry.

If either condition is not met, keep `Audit` and run another window.
