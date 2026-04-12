# Crossplane Operations Runbook

Quick reference for managing node infrastructure via Crossplane GitOps.

---

## Common Operations

### Add a New Compute Worker Node

**Time:** ~15 minutes

**Prerequisites:**
- Node is provisioned via Talos and joined cluster
- Node appears in `kubectl get nodes` as Ready
- WireGuard connectivity established

**Steps:**

1. **Get node details:**
   ```bash
   kubectl get nodes -o wide
   # Note: new node name and IP (e.g., atlas-203-59-106-45)
   ```

2. **Determine node tier:**
   - `compute`: General workload nodes (default)
   - `storage`: Longhorn-only nodes
   - `platform`: Control-plane (rare to add)

3. **Create ManagedNode claim:**
   ```bash
   cat >> platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml <<EOF

---
apiVersion: cryptophys.work/v1alpha1
kind: ManagedNode
metadata:
  name: atlas-203-59-106-45
  namespace: crossplane-system
spec:
  tier: compute
  customLabels:
    cryptophys.io/tier: compute
    workload.cryptophys.work/apps: "true"
    workload.cryptophys.work/compute: "true"
EOF
   ```

4. **Commit and push:**
   ```bash
   git add platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml
   git commit -m "add(compute-node): atlas-203-59-106-45"
   git push origin main
   ```

5. **Verify reconciliation:**
   ```bash
   kubectl get managednode -n crossplane-system
   # Watch for atlas-203-59-106-45: STATUS → Synced, READY → True
   
   kubectl get node atlas-203-59-106-45 -o jsonpath='{.metadata.labels}' | jq .
   # Verify: cryptophys.io/tier=compute is present
   ```

6. **Test pod scheduling:**
   ```bash
   kubectl run test --image=nginx --overrides='{"spec":{"nodeSelector":{"cryptophys.io/tier":"compute"}}}'
   kubectl logs test  # should run on new node
   kubectl delete pod test
   ```

---

### Assign Node to Ray Head Pool

**Time:** ~5 minutes

**Context:** You want a node to run Ray head pods (cerebrum, aide, mcp Ray heads).

**Steps:**

1. **Find available ray-head nodes:**
   ```bash
   kubectl get nodes -L ray-head | grep "true"
   # Currently: synapse, cerebellum, quanta
   ```

2. **If adding new Ray head node, update ManagedNode claim:**
   ```bash
   # Edit platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml
   # For node: atlas-203-59-106-45
   
   spec:
     tier: compute
     taints:
     - key: ray-head
       value: "true"
       effect: NoSchedule
     customLabels:
       ray-head: "true"
       cryptophys.io/tier: compute
       # ... other labels
   ```

3. **Commit and push:**
   ```bash
   git add platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml
   git commit -m "feat(ray-head): add atlas-203-59-106-45 to ray-head pool"
   git push origin main
   ```

4. **Verify:**
   ```bash
   kubectl get node atlas-203-59-106-45 -o jsonpath='{.spec.taints}' | jq '.[] | select(.key == "ray-head")'
   # Expected: {key: ray-head, value: "true", effect: NoSchedule}
   ```

5. **Optional: Pin specific Ray head to this node:**
   ```bash
   # If you want aide-mesh head always on atlas:
   cat > /tmp/placement-patch.yaml <<EOF
   apiVersion: cryptophys.work/v1alpha1
   kind: WorkloadPlacement
   metadata:
     name: aide-mesh-ray-head
     namespace: crossplane-system
   spec:
     targetWorkload:
       kind: RayService
       name: aide-mesh
       namespace: aide
     placement:
       tier: compute
       preferredNode: atlas-203-59-106-45
   EOF
   
   kubectl apply -f /tmp/placement-patch.yaml
   # Or update platform/infrastructure/crossplane-crs/claims-workload-placement.yaml in git
   ```

---

### Drain Node for Maintenance

**Time:** ~10-30 minutes (depends on workloads)

**Context:** Node needs maintenance (kernel update, disk replacement, etc.).

**Steps:**

1. **Mark node as draining in ManagedNode claim:**
   ```bash
   # Edit platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml
   # For node: campus-212-47-66-101
   
   spec:
     tier: storage
     customLabels:
       draining: "true"  # Add this flag
       # ... other labels
   ```

2. **Also update corresponding longhorn-node-*.yaml:**
   ```bash
   # Edit platform/infrastructure/storage/longhorn-node-campus-212-47-66-101.yaml
   
   spec:
     allowScheduling: false  # Disable new PVC scheduling
     evictionRequested: true  # Evict existing volumes
   ```

3. **Commit and push:**
   ```bash
   git add platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml \
           platform/infrastructure/storage/longhorn-node-campus-212-47-66-101.yaml
   git commit -m "maint(drain): campus-212-47-66-101"
   git push origin main
   ```

4. **Monitor workload migration:**
   ```bash
   # Watch Longhorn volume migration
   kubectl get pvc -A -w | grep campus
   
   # Check for remaining pods
   kubectl get pods -A -o wide | grep campus
   # Should be zero after Longhorn eviction completes
   ```

5. **Once empty, cordoning Talos-side:**
   ```bash
   # In Talos console or via talosctl
   talosctl health -n 10.8.0.5  # for campus node
   # (optional: shutdown if replacing hardware)
   ```

6. **Re-enable when ready:**
   ```bash
   # Revert draining labels in claims
   git revert <commit-hash>
   # Or manually edit and remove draining: "true", set allowScheduling: true
   git push origin main
   ```

---

### Remove Node from Cluster

**Time:** ~5 minutes (+ cleanup time)

**Context:** Node is being decommissioned permanently.

**Steps:**

1. **Remove ManagedNode claim:**
   ```bash
   # Edit platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml
   # Delete the entire YAML block for the node
   
   git add platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml
   git commit -m "remove(node): campus-212-47-66-101 decommissioned"
   git push origin main
   ```

2. **Remove longhorn-node config:**
   ```bash
   git rm platform/infrastructure/storage/longhorn-node-campus-212-47-66-101.yaml
   git commit -m "remove(storage): campus-212-47-66-101 decommissioned"
   git push origin main
   ```

3. **Verify Crossplane cleanup:**
   ```bash
   kubectl get managednode -n crossplane-system
   # campus-212-47-66-101 should disappear within 5 minutes
   ```

4. **Remove from cluster (Talos):**
   ```bash
   talosctl reset -n 10.8.0.5  # destroys node config
   # or just shut down hardware
   ```

---

### Pin a Workload to a Specific Node

**Time:** ~10 minutes

**Context:** You want a Deployment or RayService to always run on a particular node.

**Examples:**
- `cerebrum-core` → `nexus` (for local model inference)
- `aide-mesh` RayService head → `quanta` (for bridge-system access)

**Steps:**

1. **Create or update WorkloadPlacement claim:**
   ```bash
   cat >> platform/infrastructure/crossplane-crs/claims-workload-placement.yaml <<EOF

---
apiVersion: cryptophys.work/v1alpha1
kind: WorkloadPlacement
metadata:
  name: my-app-placement
  namespace: crossplane-system
spec:
  targetWorkload:
    kind: Deployment  # or RayService
    name: my-app
    namespace: my-namespace
  placement:
    tier: compute
    preferredNode: nexus-144-91-103-10  # optional: specific hostname
EOF
   ```

2. **For RayService, ensure it supports ray-head taint:**
   ```yaml
   # In the RayService manifest (apps-gitops)
   spec:
     rayClusterConfig:
       headGroupSpec:
         template:
           spec:
             # These tolerations will match quanta node taints
             tolerations:
             - key: bridge-system
               operator: Equal
               value: "true"
               effect: NoSchedule
             - key: dao-system
               operator: Equal
               value: "true"
               effect: NoSchedule
   ```

3. **Commit and push (platform-gitops):**
   ```bash
   git add platform/infrastructure/crossplane-crs/claims-workload-placement.yaml
   git commit -m "feat(placement): pin my-app to nexus"
   git push origin main
   ```

4. **Verify patch was applied:**
   ```bash
   kubectl get deployment my-app -n my-namespace -o yaml | grep -A 5 nodeSelector
   # Expected: cryptophys.io/tier: compute
   
   kubectl get deployment my-app -n my-namespace -o yaml | grep -A 10 "nodeAffinity"
   # Expected: preferredDuringSchedulingIgnoredDuringExecution with nexus-144-91-103-10
   ```

5. **Test scheduling:**
   ```bash
   kubectl rollout restart deployment/my-app -n my-namespace
   kubectl get pods -n my-namespace -o wide
   # Should run on nexus node
   ```

---

### Change Node Pool (e.g., apps-ha → platform-ha)

**Time:** ~10 minutes

**Context:** Moving a node between workload pools. **WARNING:** Will evict all pods!

**Steps:**

1. **Update ManagedNode claim:**
   ```bash
   # Edit platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml
   # For synapse node: change from apps-ha to platform-ha
   
   Before:
   spec:
     taints:
     - key: cryptophys.io/pool
       value: apps-ha
       effect: NoSchedule
   
   After:
   spec:
     taints:
     - key: cryptophys.io/pool
       value: platform-ha
       effect: NoSchedule
   ```

2. **Commit and push:**
   ```bash
   git add platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml
   git commit -m "chore(pool): synapse from apps-ha to platform-ha"
   git push origin main
   ```

3. **Monitor eviction:**
   ```bash
   kubectl get pods -A -o wide --watch | grep synapse
   # Watch as pods are evicted and rescheduled
   
   # If pods get stuck:
   kubectl delete pod <stuck-pod> -n <namespace>
   ```

4. **Verify taint changed:**
   ```bash
   kubectl get node synapse-161-97-136-251 -o jsonpath='{.spec.taints}' | jq '.[].value'
   # Expected: platform-ha (not apps-ha)
   ```

---

### Audit Node Labels & Taints

**Time:** ~10 minutes

**Context:** Verify cluster state matches Crossplane claims (detect drift).

**Steps:**

1. **Export live cluster state:**
   ```bash
   kubectl get nodes -o json | jq '.items[] | {
     name: .metadata.name,
     labels: .metadata.labels | keys,
     taints: .spec.taints | map(.key)
   }' > /tmp/live-state.json
   ```

2. **Check ManagedNode claims:**
   ```bash
   cat platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml | grep -A 20 "kind: ManagedNode"
   # Manually compare customLabels and taints with live state
   ```

3. **If drift detected, force reconciliation:**
   ```bash
   # Delete and recreate ManagedNode to force patch
   kubectl delete managednode cortex-178-18-250-39 -n crossplane-system
   
   # Automatically recreates from claim
   kubectl get managednode cortex-178-18-250-39 -n crossplane-system -w
   # Watch: STATUS → Synced, READY → True
   
   # Re-verify:
   kubectl get node cortex-178-18-250-39 -o jsonpath='{.metadata.labels}' | jq .
   ```

4. **Generate audit report:**
   ```bash
   # Create table of expected vs actual
   echo "Node,Expected Labels,Actual Labels,Match?"
   for node in $(kubectl get nodes -o name | cut -d/ -f2); do
     expected=$(grep -A 10 "name: $node" platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml | grep -oP 'customLabels:' | wc -l)
     actual=$(kubectl get node $node -o json | jq '.metadata.labels | length')
     echo "$node,$expected,$actual,$([ "$expected" -eq "$actual" ] && echo 'YES' || echo 'NO')"
   done
   ```

---

## Troubleshooting

### ManagedNode stuck in "Syncing" state

**Symptoms:**
```bash
kubectl get managednode -n crossplane-system
# STATUS: Syncing (for > 5 minutes)
```

**Diagnosis:**
```bash
kubectl describe managednode <name> -n crossplane-system
# Look for "Conditions" → Reason: "SyncError" or similar
```

**Common Causes & Fixes:**

1. **Provider credentials expired:**
   ```bash
   kubectl get secret -n crossplane-system | grep provider-config
   # Check if secret is valid
   ```

2. **Manifest schema error:**
   ```bash
   kubectl get managednode <name> -n crossplane-system -o yaml | grep -A 30 "status:"
   # Look for error message in status.conditions
   ```

3. **Force reconciliation:**
   ```bash
   kubectl delete managednode <name> -n crossplane-system
   # Re-creates automatically from claim
   ```

---

### Pod stuck in Pending with taint toleration error

**Symptoms:**
```bash
kubectl describe pod <name> -n <ns>
# Events: 0/10 nodes are available. 10 node(s) had taint {...}, pod does not tolerate it
```

**Fix:**

1. **Check pod's tolerations:**
   ```bash
   kubectl get pod <name> -n <ns> -o yaml | grep -A 10 tolerations:
   ```

2. **Check node's taints:**
   ```bash
   kubectl get node <target-node> -o jsonpath='{.spec.taints}' | jq .
   ```

3. **Add matching toleration to Deployment:**
   ```yaml
   spec:
     template:
       spec:
         tolerations:
         - key: ray-head
           operator: Equal
           value: "true"
           effect: NoSchedule
   ```

4. **Or use WorkloadPlacement to auto-add tolerations:**
   ```bash
   # (Planned: WorkloadPlacement will auto-inject common tolerations)
   ```

---

### Workload not pinning to preferred node

**Symptoms:**
```bash
kubectl get workloadplacement <name> -n crossplane-system
# STATUS: Synced, but pod still runs on different node
```

**Diagnosis:**

1. **Check if WorkloadPlacement was applied:**
   ```bash
   kubectl get pod <name> -n <ns> -o yaml | grep -A 30 affinity:
   # Should see nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution
   ```

2. **If not present, check Crossplane resource:**
   ```bash
   kubectl get <workload-kind> <workload-name> -n <ns> -o yaml | tail -50
   # If no affinity, Crossplane hasn't patched yet
   ```

3. **Force Crossplane re-sync:**
   ```bash
   kubectl patch workloadplacement <name> -n crossplane-system -p '{"metadata":{"annotations":{"crossplane.io/external-name":"<name>"}}}' --type=merge
   ```

4. **If pod is already running:**
   ```bash
   kubectl rollout restart deployment/<name> -n <ns>
   # New pod will pick up affinity and schedule to preferred node
   ```

---

## Glossary

| Term | Definition |
|------|-----------|
| **Claim** | A user-facing resource (e.g., ManagedNode) that declares desired state |
| **Composite (X-resource)** | Internal Crossplane resource (e.g., XManagedNode) that unifies claims |
| **Composition** | Template rules that sync claims to actual Kubernetes objects (e.g., Node labels) |
| **Drift** | When actual cluster state differs from git-declared state (e.g., label manually removed) |
| **Tier** | Node categorization: platform (control-plane), compute (workload), storage (Longhorn) |
| **Pool** | Logical grouping of nodes by taint: apps-ha, platform-ha, storage-only |
| **Toleration** | Pod spec rule allowing it to schedule on tainted nodes |
| **Preferred Affinity** | Pod hint for preferred (but not required) node placement |

---

## Emergency Contacts

- **Crossplane Issues:** Check Crossplane controller logs in `crossplane-system` namespace
- **Longhorn Issues:** Check Longhorn manager in `longhorn-system` namespace
- **Node Stuck:** SSH to node via WireGuard IP (see `CLAUDE.md` for IP table)

---

**Last Updated:** 2026-04-12  
**Next Revision:** 2026-05-12
