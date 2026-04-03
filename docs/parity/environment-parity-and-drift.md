# Environment Parity and Drift Audit Baseline

## Objective
Keep `talos-prod` and `cryptophys-genesis` intentionally aligned with explicit, documented variance.

## Canonical Model
- Define canonical baseline by capability domain (controllers, policy, storage, secrets, observability, gateway, backup).
- Represent intentional variance in dedicated variance entries, not implicit divergence.

## Known Structural Differences (Current)
- `cryptophys-genesis` includes additional staged resources (e.g. flux automation, extra CR packs, resource governance, kueue).
- `talos-prod` uses a narrower staged sequence.

## Drift Audit Cadence
- Weekly automated drift report.
- Mandatory drift review before promotion windows.

## Drift Report Scope
- Kustomization stage differences.
- HelmRelease and source reference differences.
- Policy and PolicyException differences.
- Cluster runtime capability deltas (security/runtime/observability).

## Acceptance Criteria
- Every cross-cluster difference is either:
  - documented intentional variance, or
  - queued remediation with owner and target date.
