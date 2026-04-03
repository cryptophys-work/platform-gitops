# Repository Architecture Index

## Cluster Entry Points
- `/home/runner/work/platform-gitops/platform-gitops/clusters/talos-prod/kustomization.yaml`
- `/home/runner/work/platform-gitops/platform-gitops/clusters/cryptophys-genesis/kustomization.yaml`

## Stage-to-Source Mapping

### talos-prod stages
- `00-crds.yaml` -> `platform/infrastructure/crds`
- `01-namespaces.yaml` -> `platform/infrastructure/namespaces`
- `02-scheduling.yaml` -> `platform/infrastructure/scheduling`
- `05-sources.yaml` -> `platform/infrastructure/sources`
- `10-controllers.yaml` -> `platform/infrastructure/controllers`
- `10-database.yaml` -> `platform/infrastructure/database`
- `12-certificates.yaml` -> `platform/infrastructure/certificates`
- `15-dns-core.yaml` -> `platform/infrastructure/dns-core`
- `15-security-runtime.yaml`, `15-security-runtime-crs.yaml` -> `platform/security` and runtime CRs
- `17-metallb.yaml` -> `platform/infrastructure/metallb`
- `18-networking.yaml` -> `platform/infrastructure/networking`
- `20-policy.yaml`, `21-policy-ssot.yaml`, `22-policy-reporter.yaml` -> `platform/infrastructure/policy*`
- `30-storage.yaml` -> `platform/infrastructure/storage`
- `31-vault.yaml` -> `platform/infrastructure/vault-system`
- `32-spire.yaml` -> `platform/infrastructure/spire`
- `34-harbor.yaml` -> `platform/infrastructure/harbor`
- `35-secrets.yaml` -> `platform/infrastructure/secrets`
- `36-gitea.yaml` -> `platform/infrastructure/gitea`
- `37-argocd.yaml` -> `platform/infrastructure/argocd`
- `38-observability.yaml` -> `platform/infrastructure/observability`
- `39-security-observability.yaml` -> `platform/infrastructure/security-observability`
- `40-backup.yaml` -> `platform/infrastructure/backup`
- `41-crossplane.yaml` -> `platform/infrastructure/crossplane`
- `42-ray.yaml` -> `platform/infrastructure/ray`
- `43-gateway.yaml` -> `platform/infrastructure/gateway`

### cryptophys-genesis stages
Includes equivalent capability domains with additional stages:
- Flux automation/system stages (`06`, `07`)
- Additional governance/runtime stages (`12-kueue`, `18-resource-governance`)
- Additional CR-specific stages for argocd, backup, crossplane.

## Ownership
See `/home/runner/work/platform-gitops/platform-gitops/docs/governance/docs-ownership.md`.
