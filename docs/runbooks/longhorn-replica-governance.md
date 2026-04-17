# Longhorn: replica governance, rollout, and storage growth

Reference for how cryptophys classifies Longhorn replica policy in GitOps. Live PVC and Longhorn volume state are observed with standard cluster tooling (`kubectl`, Longhorn UI) — not vendored in this repository.

## 1. PVC / volume classification (design intent)

| Tier | Examples (GitOps) | Replica policy |
|------|-------------------|----------------|
| **A — critical** | Vault, Gitea, CNPG/Postgres HA, ArgoCD Redis HA, Harbor (`longhorn-harbor-retain`) | Do not reduce; Harbor stays at 3× via SC |
| **B — high** | SPIRE, MinIO backup, NATS JetStream, Trivy | Follow existing SC (often 1× with compensating controls) |
| **C — non-critical** | CI workspaces, caches, rebuildable app data | Prefer `longhorn-noncritical` or `longhorn-single` (both 1×) |

Default Helm values keep **2×** for the default StorageClass — see `platform/infrastructure/storage/longhorn/values.yaml`. Changing the global default affects every new `longhorn` PVC; prefer per-SC or per-volume tuning for Tier C.

## 2. Target replica matrix

| StorageClass | Replicas | Use |
|--------------|---------|-----|
| `longhorn-harbor-retain` | 3 | Harbor registry/chart DB |
| `longhorn`, `longhorn-retain`, `longhorn-transient` | 2 | General / retained / transient with snapshot jobs |
| `longhorn-single`, `longhorn-backup`, `longhorn-spire-data`, `longhorn-noncritical` | 1 | Single-replica classes (cost / locality tradeoff) |

**Candidates to lower footprint:** volumes still on default `longhorn` (2×) that are Tier C → migrate to `longhorn-noncritical` (new PVC + copy) or patch Volume spec in maintenance window. Do not lower Harbor or Vault-tier volumes.

## 3. Rollout batches + stop/go

1. **Batch 0 — observe:** no changes; baseline Longhorn UI + node disk headroom.
2. **Batch 1 — one Tier C namespace:** single PVC test; validate app after replica/SC change.
3. **Batch 2+:** repeat per namespace or app; pause between batches 24–48h if possible.

**Go when:**

- No volumes `Faulted`; degraded count within team SLO.
- Enough schedulable space on Longhorn nodes (maintain operator-defined headroom, e.g. ≥15% free on data disks).
- CSI attach/detach error rate normal.

**Stop / hold when:**

- Rebuild storms, recurring `Faulted`, or control-plane/API instability.
- Insufficient healthy nodes to satisfy even 1× repl placement (`best-effort` still needs a node).

## 4. Monitoring signals (sustained growth and hygiene)

Observability and capacity reviews should cover: per-node disk utilization (Longhorn + node metrics), largest growing PVCs over time, Released PVs and stale snapshots, RecurringJob health for transient snapshot policies, and periodic audit of StorageClass choice (`longhorn` vs `longhorn-noncritical` / `longhorn-single`) for Tier C workloads.

## 5. GitOps reference

- Helm values: `platform/infrastructure/storage/longhorn/values.yaml`
- StorageClasses: `platform/infrastructure/storage/`, `argocd/`, `harbor/`, `backup/`, `spire/`
