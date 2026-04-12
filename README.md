# Cryptophys Platform GitOps

Source of truth for the platform layer managed by Flux.

## Repository Scope

Cryptophys operates with three GitOps repositories:

- `platform-gitops` - platform and cluster infrastructure managed by Flux
- `apps-gitops` - application layer managed by ArgoCD
- `ssot-core` - contracts, policy, schema, and operational documentation

## Current Structure

```text
platform-gitops/
├── clusters/talos-prod/kustomization/
│   ├── 00-crds.yaml
│   ├── 01-namespaces.yaml
│   ├── 02-scheduling.yaml
│   ├── 05-sources.yaml
│   ├── 10-controllers.yaml
│   ├── 10-database.yaml
│   ├── 12-certificates.yaml
│   ├── 15-dns-core.yaml
│   ├── 15-security-runtime-crs.yaml
│   ├── 15-security-runtime.yaml
│   ├── 17-metallb.yaml
│   ├── 18-networking.yaml
│   ├── 20-policy.yaml
│   ├── 21-policy-ssot.yaml
│   ├── 22-policy-reporter.yaml
│   ├── 30-storage.yaml
│   ├── 31-vault.yaml
│   ├── 32-spire.yaml
│   ├── 34-harbor.yaml
│   ├── 35-secrets.yaml
│   ├── 36-gitea.yaml
│   ├── 37-argocd.yaml
│   ├── 38-observability.yaml
│   ├── 39-security-observability.yaml
│   ├── 40-backup.yaml
│   ├── 41-crossplane.yaml
│   ├── 42-ray.yaml
│   └── 43-gateway.yaml
└── platform/infrastructure/
    ├── argocd/
    ├── certificates/
    ├── controllers/
    ├── crds/
    ├── database/
    ├── dns/
    ├── gateway/
    ├── gitea/
    ├── harbor/
    ├── kueue/
    ├── metallb/
    ├── namespaces/
    ├── networking/
    ├── observability/
    ├── policy/
    ├── policy-reporter/
    ├── policy-ssot/
    ├── scheduling/
    ├── secrets/
    ├── security-observability/
    ├── sources/
    ├── spire/
    ├── storage/
    ├── tekton/
    └── vault-system/
```

The authoritative deployment order is the contents of `clusters/talos-prod/kustomization/`.

## Internal Git Endpoints

- `http://gitops-gitea-http.gitops-system.svc.cluster.local:3000/cryptophys-work/platform-gitops.git`
- `http://gitops-gitea-http.gitops-system.svc.cluster.local:3000/cryptophys-work/apps-gitops.git`
- `http://gitops-gitea-http.gitops-system.svc.cluster.local:3000/cryptophys-work/ssot-core.git`

## Operational Notes

- `HelmRepository` uses `source.toolkit.fluxcd.io/v1beta2`
- `HelmRelease` uses `helm.toolkit.fluxcd.io/v2beta2`
- For Longhorn CRD ownership conflicts, use `docs/runbooks/LONGHORN_CRD_ADOPTION_RECOVERY.md`

## Governance and References

- Branch protection and merge blocking: `docs/governance/branch-protection-and-merge-blocking.md`
- Cross-repo contract model: `docs/contracts/cross-repo-contract-model.md`
- Environment parity and drift: `docs/parity/environment-parity-and-drift.md`
- Stage-to-source mapping: `docs/architecture/repo-architecture-index.md`
- Runbook standards and ownership:
  - `docs/operations/runbook-standard.md`
  - `docs/governance/docs-ownership.md`
