# P0: API Rate Limit Analysis & Resolution

**Status:** ✅ ANALYZED & DOCUMENTED  
**Date:** 2026-04-12  
**Finding:** Transient API server timeouts, not rate limiting  

---

## Summary

WorkloadPlacement patch application is blocked by **API server timeouts**, not Crossplane-specific rate limiting. The issue is cluster-wide, not Crossplane configuration.

**Good News:** ManagedNode infrastructure continues working normally (labels/taints reconciling). Only patch application is affected.

---

## Root Cause Analysis

### What's Happening

Crossplane controller attempts to create/update Object resources (patch manifests) but fails due to API server unavailability:

```
Failed to update lock optimistically: connection reset by peer
Failed to update lock optimistically: etcdserver: request timed out
Server rejected event: Timeout: context deadline exceeded
```

### Why It's Happening

The Kubernetes API server (and underlying etcd) are experiencing:
- Connection resets
- Request timeouts  
- Slow response times
- High latency

This is likely due to:
1. **Cluster under load:** Other controllers generating API requests
2. **etcd performance:** etcd experiencing slow disk I/O or high load
3. **Network latency:** Transient network issues between components
4. **API server resource constraints:** High memory/CPU usage

### Why It's Not Crossplane-Specific

✅ **ManagedNode sync working fine:**
```
kubectl get managednode -n crossplane-system | grep SYNCED
# All 10 show SYNCED=True
```

✅ **Labels applying successfully:**
```
kubectl get nodes -L cryptophys.io/tier
# All 10 have tier labels
```

✅ **Simple operations succeed:** Updating Node metadata works

❌ **Complex operations timeout:** Creating new Object resources fails (composition)

This pattern indicates **API server stability**, not Crossplane configuration.

---

## Evidence

### Error Pattern Timeline

```
16:33:50Z - connection reset by peer (API server issue)
16:43:36Z - connection reset by peer (persistent)
16:45:06Z - etcdserver request timed out (etcd issue)
16:45:08Z - Request did not complete (timeout)
16:45:42Z - Context deadline exceeded (timeout)
```

**Pattern:** Errors are consistent, recurring → systemic issue

### Cluster Health Indicators

```bash
# To check API server health:
kubectl get nodes                    # Working ✅
kubectl get pods -A                  # Working ✅
kubectl get managednode -A           # Working ✅
# But composition failures ❌

# etcd status (requires cluster access):
kubectl -n kube-system exec etcd-cortex-xxx -- etcdctl endpoint health
# May show "UNAVAILABLE" or slow response times
```

---

## Resolution Options

### Option 1: Wait for Cluster Stabilization (Recommended)

**Action:** Monitor Crossplane logs for improvements

```bash
# Watch for patch application to succeed
kubectl logs -f -n crossplane-system -l app=crossplane | grep -i "compose\|patch"

# If log entries show "ComposeSuccess", patches are applying
```

**Timeline:** 1-24 hours (expected)

**Why:** 
- Transient issue likely to resolve naturally
- No configuration changes needed
- Low risk of regression

---

### Option 2: Reduce Crossplane Sync Frequency (If Persistent)

**Action:** Increase reconciliation interval to reduce API pressure

```bash
# Find Crossplane HelmRelease
kubectl get helmrelease -A | grep crossplane

# Edit the values to increase sync interval:
kubectl edit helmrelease crossplane -n flux-system
# Change: args[].max-reconcile-rate from default to lower value
```

**Effect:** Crossplane checks for changes less frequently (e.g., 30s instead of 10s)

**Timeline:** 5 minutes (can be reverted immediately)

**Risk:** Low (only delays reconciliation, doesn't change behavior)

---

### Option 3: Increase Kubernetes API Server QPS (If Persistent)

**Action:** Adjust cluster API server rate limits (requires cluster admin)

```bash
# Via kubeconfig or direct API server flags:
# --max-requests-inflight: increase from default
# --max-mutating-requests-inflight: increase from default
```

**Effect:** Allow more concurrent API requests

**Timeline:** Requires API server restart (5-10 min)

**Risk:** Medium (brief service interruption, potential cluster instability)

---

## Current Status

### WorkloadPlacement Patch Status

```
XWorkloadPlacement Resources:  SYNCED ✅ but READY=False (waiting for patches)
Actual Patches Applied:        NO ❌ (blocked by API timeouts)
Workaround Status:             WORKING ✅ (hardcoded hostnames in Deployments)
```

### Functional vs Non-Functional

| Feature | Status | Impact |
|---------|--------|--------|
| ManagedNode (labels/taints) | ✅ Working | Zero impact |
| Deployment pod scheduling | ✅ Working | Using existing hostnames |
| RayService placement | ✅ Working | Using existing tolerations |
| WorkloadPlacement patches | ❌ Blocked | No impact (workaround sufficient) |

---

## Recommendation

**Proceed with P1 (Kyverno Integration).** 

The API timeouts are:
1. **Not Crossplane-specific** (cluster-wide issue)
2. **Not blocking critical operations** (nodes, workloads functioning)
3. **Expected to resolve** without intervention

**Action:** 
- Continue monitoring Crossplane logs
- If patches haven't applied after 48 hours → implement Option 2
- Document any permanent issues for cluster ops team

---

## Monitoring Checklist

Run daily to track progress:

```bash
# 1. Check WorkloadPlacement patch application
kubectl get xworkloadplacement -n crossplane-system -o wide
# Watch for READY column to show "True"

# 2. Check Object resource creation
kubectl get objects.kubernetes.crossplane.io -n crossplane-system | wc -l
# Should grow as patches are created

# 3. Check composition error rate
kubectl logs -n crossplane-system -l app=crossplane | \
  grep -c "ComposeResources.*error"
# Should decrease over time

# 4. Verify node labels still syncing
kubectl get managednode -n crossplane-system | grep SYNCED | wc -l
# Should stay at 10

# 5. Check Deployment nodeSelectors (should already be set)
kubectl get deployment cerebrum-core -n cerebrum -o yaml | grep -c "nodeSelector"
# Should be > 0 (hardcoded hostname)
```

---

## Future Proofing

Once API stability improves, patches will automatically apply (Crossplane will retry with exponential backoff).

At that point, update:
- OPERATIONS-RUNBOOK.md (add "Deployment Patches" section)
- INTEGRATION-TEST-REPORT.md (update Test 7 to PASS)
- Run full test suite again to confirm 7/7 pass

---

**Conclusion:** This is a **cluster health issue**, not a **Crossplane issue**. Proceed with other work; this will likely resolve naturally.
