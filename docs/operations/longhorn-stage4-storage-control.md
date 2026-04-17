# Longhorn Stage-4 Storage Control

## Scope

This runbook controls Longhorn storage growth without reducing reliability for critical workloads.

## Baseline Policy

- Keep global defaults unchanged:
  - `defaultSettings.defaultReplicaCount=2`
  - `persistence.defaultClassReplicaCount=2`
- Apply selective per-volume downsizing only for non-critical detached volumes.
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

## Operational Commands

```bash
kubectl -n longhorn-system get volumes.longhorn.io --no-headers | awk '$3=="detached"{c++} END{print c+0}'
kubectl -n longhorn-system get volumes.longhorn.io --no-headers | awk '$4=="faulted"{c++} END{print c+0}'
kubectl -n longhorn-system get replicas.longhorn.io --no-headers | awk '$3=="stopped"{c++} END{print c+0}'
kubectl -n longhorn-system get volumes.longhorn.io --no-headers | awk '$3=="detached"{print $1, $6}' | sort -k2 -hr | head -10
```
