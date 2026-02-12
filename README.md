# Cryptophys Platform GitOps

Single source of truth untuk platform layer yang dikelola Flux.

## Repository Scope

Model yang dipakai adalah 3 path repo:

- `cryptophys.adm/platform-gitops` (platform layer, Flux)
- `cryptophys.adm/apps` (application layer, ArgoCD/Flux apps layer)
- `cryptophys.adm/ssot-core` (governance/contracts/policy)

Status aktual saat dokumen ini ditulis:

- `platform-gitops`: **sudah ada dan aktif**
- `apps`: **sudah dibuat dan aktif**
- `ssot-core`: **sudah dibuat dan aktif**

## Struktur Utama

```text
platform-gitops/
├── clusters/talos-prod/kustomization/
│   ├── 00-crds.yaml
│   ├── 05-sources.yaml
│   ├── 10-controllers.yaml
│   ├── 15-dns-core.yaml
│   ├── 20-policy.yaml
│   ├── 30-storage.yaml
│   ├── 40-observability.yaml
│   └── 90-aide-sensors.yaml
└── platform/infrastructure/
    ├── crds/
    ├── sources/
    ├── controllers/
    ├── dns/
    ├── policy/
    ├── storage/
    ├── observability/
    └── aide/
```

## Endpoint Git Internal (Cluster)

- `http://gitea-http.gitea.svc.cluster.local:3000/cryptophys.adm/platform-gitops.git`
- `http://gitea-http.gitea.svc.cluster.local:3000/cryptophys.adm/apps.git`
- `http://gitea-http.gitea.svc.cluster.local:3000/cryptophys.adm/ssot-core.git`

## Catatan Operasional

- `HelmRepository` menggunakan `source.toolkit.fluxcd.io/v1beta2`.
- `HelmRelease` menggunakan `helm.toolkit.fluxcd.io/v2beta2`.
- Jika terjadi konflik ownership CRD (kasus Longhorn), gunakan runbook:
  - `docs/runbooks/LONGHORN_CRD_ADOPTION_RECOVERY.md`
