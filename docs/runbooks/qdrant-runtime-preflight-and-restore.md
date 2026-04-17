# Qdrant Runtime Preflight and Restore

## Scope
Operational checklist for Qdrant-first deployment phases:
- Runtime preflight (scheduler/PVC/readiness)
- Snapshot and restore drill evidence

## Runtime Preflight
1. Confirm target nodes match selector and tolerate required taints.
2. Confirm PVC is `Bound` before rollout.
3. Confirm pod reaches `Running` and readiness probe is healthy.
4. Confirm service endpoint is populated.
5. Confirm `GET /readyz` and a sample collection query succeed.

## Snapshot Policy
- Cron schedule: every 6 hours.
- Retention: keep latest successful snapshots based on storage budget.
- Snapshot API target: `POST /collections/{collection}/snapshots`.

## Restore Drill
1. Select a known snapshot timestamp.
2. Restore into a non-production validation collection or isolated environment.
3. Run smoke queries for known `tenant_id` and expected payload metadata.
4. Record measured RTO and RPO.
5. Publish drill evidence link in release notes.

## Exit Gates
- Runtime stable for 24h without scheduling flaps.
- At least one successful restore drill with accepted RTO/RPO.
- Alerting active for pod readiness and gateway availability.
