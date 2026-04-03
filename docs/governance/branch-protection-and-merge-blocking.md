# Branch Protection and Merge Blocking Policy

## Objective
Prevent broken GitOps states from merging into protected branches.

## Protected Branches
- `main`
- release branches: `release/*`

## Required Status Checks
The following checks MUST pass before merge:
- `yaml-lint`
- `kustomize-build (talos-prod)`
- `kustomize-build (cryptophys-genesis)`
- `schema-validate (talos-prod)`
- `schema-validate (cryptophys-genesis)`
- `policy-check (talos-prod)`
- `policy-check (cryptophys-genesis)`
- `required-gates`

## Required Review Controls
- At least 1 approving review for non-trivial changes.
- Dismiss stale approvals on new commits.
- Require conversation resolution before merge.

## Signing Controls
- Require signed commits on protected branches.
- Require signed tags for release tags.
- Contributors must configure signing before merging:
  - Commit signing: GitHub Docs -> "Tell Git about your signing key"
  - Tag signing: Git documentation -> signed tags (`git tag -s`)

## Failed Reconciliation Blocker
If any of the following conditions occur in CI validation or post-merge reconciliation evidence, merge is blocked until resolved:
- Kustomize build failure for any managed cluster path.
- Schema validation failure for changed manifests.
- Policy validation indicates enforcement-breaking changes without approved exception.
- Flux reconciliation in target environment indicates failed or degraded status caused by the PR changes.

## Exception Handling
- Emergency overrides require approval from platform owner and security owner.
- Every override requires issue tracking with remediation deadline.
