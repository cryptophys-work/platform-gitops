# Observability Stack Scale-Down Report

**Date:** 2026-02-14 05:52 UTC  
**Reason:** Cluster stability prioritization after cortex node recovery  
**Status:** ✅ Complete

---

## Summary

Scaled down entire observability stack to 0 replicas to reduce resource consumption on control-plane nodes and ensure cluster stability.

### Resource Savings

| Component | CPU Freed | Memory Freed | Previous Replicas | Current Replicas |
|-----------|-----------|--------------|-------------------|------------------|
| Prometheus | ~500m | ~2Gi | 1 | 0 |
| Grafana | ~100m | ~256Mi | 2 (crashed) | 0 |
| AlertManager | ~50m | ~128Mi | 1 | 0 |
| Loki | ~100m | ~512Mi | 1 | 0 |
| OTEL Collector | ~50m | ~128Mi | 1 | 0 |
| Kube-State-Metrics | ~50m | ~128Mi | 1 | 0 |
| Prometheus Operator | ~50m | ~64Mi | 1 | 0 |
| **Total** | **~900m** | **~3.2Gi** | **8** | **0** |

### Node Resource Usage (Post Scale-Down)

```
Control-Plane Nodes:
  corpus:    4694m CPU (78%)  7633Mi MEM (67%)  [High, monitor]
  cortex:    3467m CPU (58%)  7224Mi MEM (63%)  [Acceptable]
  cerebrum:  2981m CPU (50%)  6529Mi MEM (57%)  [Acceptable]

Worker Nodes (Cordoned):
  aether:    254m CPU (6%)    1667Mi MEM (22%)  [Idle]
  campus:    238m CPU (12%)   907Mi MEM (26%)   [Idle]
```

---

## Actions Taken

### Workloads Scaled to Zero

```bash
kubectl scale deployment -n observability platform-observability-otel-collector-opentelemetry-collector --replicas=0
kubectl scale deployment -n observability platform-observability-pro-operator --replicas=0
kubectl scale deployment -n observability platform-observability-prometheus-kube-state-metrics --replicas=0
kubectl scale deployment -n observability platform-observability-prometheus-grafana --replicas=0
kubectl scale statefulset -n observability alertmanager-platform-observability-pro-alertmanager --replicas=0
kubectl scale statefulset -n observability platform-observability-loki --replicas=0
kubectl scale statefulset -n observability prometheus-platform-observability-pro-prometheus --replicas=0
```

### Pods Cleaned

- Deleted 2 crashed Grafana pods (CrashLoopBackOff)
- Deleted 3 completed/pending synthetic checker pods

---

## Data Preservation

✅ **All data preserved for future scale-up:**

- PVCs retained (Prometheus, Grafana, Loki, AlertManager data)
- ConfigMaps and Secrets retained
- Prometheus Operator CRDs retained
- Namespace `observability` preserved (empty)

---

## Scale-Up Procedure (When Ready)

```bash
# Scale up in order (operator first, then data stores, then collectors)
kubectl scale deployment -n observability platform-observability-pro-operator --replicas=1
sleep 10

kubectl scale statefulset -n observability prometheus-platform-observability-pro-prometheus --replicas=1
kubectl scale statefulset -n observability alertmanager-platform-observability-pro-alertmanager --replicas=1
kubectl scale statefulset -n observability platform-observability-loki --replicas=1
sleep 30

kubectl scale deployment -n observability platform-observability-prometheus-grafana --replicas=1
kubectl scale deployment -n observability platform-observability-otel-collector-opentelemetry-collector --replicas=1
kubectl scale deployment -n observability platform-observability-prometheus-kube-state-metrics --replicas=1

# Verify pods are running
kubectl get pods -n observability -w
```

---

## Monitoring Without Observability Stack

Use kubectl commands for manual cluster monitoring:

```bash
# Node resource usage
kubectl top nodes --sort-by=cpu
kubectl top nodes --sort-by=memory

# Pod resource usage
kubectl top pods -A --sort-by=memory | head -20
kubectl top pods -A --sort-by=cpu | head -20

# Pod health
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded

# Recent events
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# API server health
kubectl get pods -n kube-system -l component=kube-apiserver
kubectl get --raw /healthz
kubectl get componentstatuses
```

---

## Current Cluster Status

### Critical Services (Operational)

- ✅ Harbor: 7/7 pods ready
- ✅ Gitea: 9/9 pods ready
- ✅ Crossplane: 4/4 pods ready
- ✅ Kyverno: Active
- ✅ Cilium: Stable
- ✅ Longhorn: Healthy

### Deferred Work (Waiting for Stability)

- ⏸️ Kaniko pipeline migration
- ⏸️ Harbor image migration (110 images)
- ⏸️ Kyverno compliance (28 images need digests)
- ⏸️ Harbor proxy cache activation
- ⏸️ Infrastructure upgrades (Harbor v2.15, Longhorn v1.7)

---

## Recommendations

1. **Monitor cluster for 1-2 hours** to verify stability
2. **Watch corpus node** (78% CPU) for resource contention
3. **Consider uncordoning worker nodes** if stable
4. **Resume deferred work** once resource usage stabilizes
5. **Scale up observability** when cluster proven stable (24h+)

---

## Related Issues

- Cortex node recovery: Completed successfully
- API-server webhook issue: Resolved (Crossplane activated)
- Harbor recovery: 7/7 pods operational
- Observability Grafana crashes: Deferred (scaled to 0)

---

## Next Session Actions

1. Monitor cluster stability metrics
2. Verify no new pod failures
3. Check API-server restart counts (should remain stable)
4. Consider worker node utilization if stability maintained
5. Resume pipeline/image work when appropriate

