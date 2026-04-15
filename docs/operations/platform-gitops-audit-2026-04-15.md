# Platform GitOps Audit — 2026-04-15

## Scope

Comprehensive audit of `platform-gitops` focused on:

- cluster stage ordering and dependency readability,
- validation automation coverage,
- architecture documentation consistency,
- policy baseline spot-check for critical namespace handling.

## Findings

### High

1. **Stage ordering drift in `clusters/talos-prod/kustomization.yaml`**
   - `12-certificates` appeared before `10-database`.
   - `15-security-runtime*` appeared after `22-policy-reporter`.
   - Impact: does not always break Flux (because `dependsOn` exists), but creates misleading deployment order and increases operator error risk during incident handling.

### Medium

1. **Missing automated guardrail for stage-order regressions**
   - Existing validation script checked renderability only, not metadata ordering consistency.

2. **Documentation drift in stage-to-source mapping**
   - `15-dns-core.yaml` was mapped to `platform/infrastructure/dns-core` while the actual source path is `platform/infrastructure/dns`.

3. **Kyverno policy list duplication**
   - `platform/infrastructure/policy/cp-restriction-policy.yaml` had duplicated namespace entry (`facilitator`) in two `NotIn.values` lists.
   - Impact: no functional outage, but raises maintenance risk and can hide accidental list drift.

4. **Inconsistent policy metadata quality**
   - Several `ClusterPolicy` objects relied on mixed annotation keys and missed standardized severity/description fields.
   - Impact: review quality and compliance checks become less deterministic.

5. **Implicit Kyverno behavior fields**
   - Some `ClusterPolicy` objects omitted `spec.validationFailureAction` and/or `spec.background`.
   - Impact: default behavior can be inferred differently during reviews; explicitness improves predictability.

### Low

1. **Policy baseline spot-check**
   - Critical namespace keywords (`kube-system`, `longhorn-system`, `cilium-system`) are present in policy manifests where expected.
   - No immediate regression found in sampled policy files.

## Improvements Applied

1. Reordered `clusters/talos-prod/kustomization.yaml` resource list to follow non-decreasing stage numbering.
2. Added `hack/lint-cluster-stage-order.sh` to enforce cluster stage-order consistency.
3. Added `hack/lint-kyverno-policy-lists.py` to detect duplicate list values in Kyverno `ClusterPolicy` manifests.
4. Wired stage-order lint and Kyverno list lint into `hack/validate-kustomize-targets.sh`.
5. Removed duplicate `facilitator` entries from `platform/infrastructure/policy/cp-restriction-policy.yaml`.
6. Updated `docs/architecture/repo-architecture-index.md` (`dns-core` mapping corrected to `dns`).
7. Updated `docs/operations/platform-gitops-validation.md` with new pre-render lint checkpoints.
8. Added `hack/lint-kyverno-policy-annotations.py` and integrated it into validation.
9. Standardized missing policy metadata in:
   - `platform/infrastructure/policy/cluster-pool-namespace-labeling.yaml`
   - `platform/infrastructure/policy/policy__cluster-pool-platform-ha-toleration.yaml`
   - `platform/infrastructure/resource-governance/kyverno-memory-guardrail.yaml`
   - `platform/infrastructure/resource-governance/kyverno-transient-storage-guardrail.yaml`
10. Added `hack/lint-kyverno-policy-behavior.py` and integrated it into validation.
11. Made Kyverno behavior explicit in:
    - `platform/infrastructure/resource-governance/kyverno-memory-guardrail.yaml`
    - `platform/infrastructure/tekton/policies/tekton-controller-harbor-images.yaml`
12. Added report generator `hack/report-kyverno-policy-compliance.py`.
13. Generated compliance inventory at `docs/operations/kyverno-policy-compliance-matrix.md`.

## Validation Evidence

Run:

```bash
bash hack/validate-kustomize-targets.sh
```

Expected success criteria:

- stage-order lint passes,
- all kustomize targets in `hack/validation-targets.txt` pass.
