# Longhorn Stage-4 Storage Control

## Scope

This runbook controls Longhorn storage growth without reducing reliability for critical workloads. It assumes **global** Helm values keep `defaultReplicaCount` and default StorageClass replica at **2**; Stage-4 only tunes **individual volumes** where policy allows.

## Baseline Policy

- Keep global defaults unchanged:
  - `defaultSettings.defaultReplicaCount=2`
  - `persistence.defaultClassReplicaCount=2`
- Apply selective per-volume downsizing only for non-critical **detached** volumes.
- Never downsize replicas for critical data services without explicit approval.

## Workload Classes

- `critical`: `vault-system`, `trustedledger`, `spire-system`, `apps-dash`, `apps-system`, `registry-system`, `mesh-system`, `minio-system`, `postgresql-system`
- `standard`: platform shared services outside critical class
- `dev-temp`: `aide`, `apps-user`, `apps-core`, `facilitator`, `orchestrator`, `cqls-compute`

## Replica Targets

- `critical`: target replica `2` (or higher if already required by service policy)
- `standard`: target replica `2`
- `dev-temp`:
  - `detached` volumes: target replica `1`
  - `attached` volumes: keep current value unless maintenance window and owner approval exist

## Crossplane & Longhorn Node (guardrail)

Each Kubernetes node must have **at most one** authoritative writer for the Longhorn `nodes.longhorn.io` CR: **`XManagedNode` / ManagedNode`** owns disk scheduling flags. The **`XLonghornRelease`** composition must **not** duplicate embedded Longhorn `Node` manifests for the same host (that caused conflicting patches and scheduling flips). If scheduling on a node looks unstable, check:

```bash
kubectl -n crossplane-system get objects.kubernetes.crossplane.io -o json | jq -r '
  .items[]
  | select(.spec.forProvider.manifest.apiVersion? == "longhorn.io/v1beta2"
      and .spec.forProvider.manifest.kind? == "Node")
  | "\(.metadata.name) ns=\(.spec.forProvider.manifest.metadata.namespace) name=\(.spec.forProvider.manifest.metadata.name) policies=\(.spec.managementPolicies // [])"
'
```

More context: [Crossplane operations runbook](../crossplane/OPERATIONS-RUNBOOK.md).

## Batch Rollout Method

1. Build candidate list:
   - class `dev-temp`
   - `state=detached`
   - `numberOfReplicas>=2`
2. Patch candidates in small batches (max 3 volumes per batch).
3. Verify after each batch:
   - No new `faulted` volumes
   - Target volumes remain `detached` and reachable
   - `stopped` replica count decreases over time
4. Stop rollout if any target becomes `degraded` or `faulted`.

### Candidate list (jq)

Uses PVC namespace from `status.kubernetesStatus` (same source as the UI). Adjust the namespace allowlist to match **dev-temp** above.

```bash
NS_REGEX='^(aide|apps-user|apps-core|facilitator|orchestrator|cqls-compute)$'
kubectl -n longhorn-system get volumes.longhorn.io -o json | jq -r --arg re "$NS_REGEX" '
  .items[]
  | select(.status.state == "detached")
  | select((.spec.numberOfReplicas // 1) >= 2)
  | . as $v
  | ($v.status.kubernetesStatus.namespace // "") as $ns
  | select($ns != "" and ($ns | test($re)))
  | "\($v.metadata.name) pvc_ns=\($ns) replicas=\($v.spec.numberOfReplicas // 0) robustness=\($v.status.robustness // "?")"
'
```

If `kubernetesStatus` is empty (orphan / edge case), intersect manually with `kubectl get pvc -A`.

### Per-volume replica reduction (example)

Only after the volume is **detached**, class is **dev-temp**, and change is approved:

```bash
VOL=pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
kubectl -n longhorn-system patch volumes.longhorn.io "$VOL" --type merge -p '{"spec":{"numberOfReplicas":1}}'
```

Longhorn will stop excess replicas over time; watch `replicas.longhorn.io` and volume health.

## Stop/Go Criteria

- `GO` when:
  - faulted volume count is unchanged (`0` increase)
  - no critical workload PVC transitions to `Pending`
- `STOP` when:
  - any new `faulted` volume appears
  - any critical namespace volume health degrades
  - API instability blocks consistent verification

## Weekly Monitoring Checklist

1. Count detached, faulted, and stopped replicas.
2. List top 10 largest detached volumes.
3. Check orphan detached volumes (not referenced by active PVC).
4. Confirm critical namespaces keep target replica policy.
5. Report trend deltas versus last week.
6. (Optional) Spot-check **scheduling**: for storage-heavy nodes, `nodes.longhorn.io` should show `spec.allowScheduling: true` and disks with `allowScheduling: true` unless intentionally evicted.

## Operational Commands

### Counts (jq — robust across column layout)

```bash
kubectl -n longhorn-system get volumes.longhorn.io -o json | jq '[.items[] | select(.status.state=="detached")] | length'
kubectl -n longhorn-system get volumes.longhorn.io -o json | jq '[.items[] | select(.status.robustness=="faulted")] | length'
kubectl -n longhorn-system get replicas.longhorn.io -o json | jq '[.items[] | select(.status.currentState=="stopped")] | length'
```

### Top detached by size (bytes in API)

```bash
kubectl -n longhorn-system get volumes.longhorn.io -o json | jq -r '
  .items[]
  | select(.status.state=="detached")
  | "\(.status.actualSize // 0) \(.metadata.name)"
' | sort -nr | head -10
```

### Table shortcuts (awk)

Default `kubectl get` output includes a **DATA ENGINE** column; `$3` is volume **STATE**, `$4` is **ROBUSTNESS**. If your client output differs, use the jq commands above instead.

```bash
kubectl -n longhorn-system get volumes.longhorn.io --no-headers | awk '$3=="detached"{c++} END{print c+0}'
kubectl -n longhorn-system get volumes.longhorn.io --no-headers | awk '$4=="faulted"{c++} END{print c+0}'
kubectl -n longhorn-system get replicas.longhorn.io --no-headers | awk '$3=="stopped"{c++} END{print c+0}'
kubectl -n longhorn-system get volumes.longhorn.io --no-headers | awk '$3=="detached"{print $1, $6}' | sort -k2 -nr | head -10
```

### Settings worth glancing at during growth control

```bash
kubectl -n longhorn-system get settings.longhorn.io \
  storage-minimal-available-percentage storage-over-provisioning-percentage replica-auto-balance \
  -o custom-columns=NAME:.metadata.name,VALUE:.value
```

## See also

- [Crossplane operations runbook](../crossplane/OPERATIONS-RUNBOOK.md) — storage nodes, Longhorn node lifecycle
- Longhorn Helm release / values: `platform/infrastructure/longhorn/` (Flux)
