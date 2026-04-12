# Crossplane Infrastructure Audit & Inventory

**Last Updated:** 2026-04-12  
**Scope:** Complete audit of Crossplane-managed, Flux-managed, and manually-managed infrastructure  
**Cluster:** cryptophys-genesis (Talos v1.12.0 / K8s v1.35.0)

---

## Executive Summary

Crossplane now manages **10 ManagedNode resources** (all cluster nodes) and **6 WorkloadPlacement resources** (Deployment + RayService heads), eliminating node label drift and hardcoded hostname coupling. The cluster infrastructure follows these principles:

- **Single Source of Truth (GitOps):** All infrastructure declared in git, no manual `kubectl` mutations
- **Continuous Reconciliation:** Crossplane watches claims and continuously reconciles actual cluster state
- **Declarative Placement:** Workload-to-node affinity via WorkloadPlacement (not hardcoded nodeSelectors)
- **Pool-Based Scheduling:** ClusterPool definitions unify namespace allowlists and node groupings

---

## Crossplane-Managed Resources

### 1. Node Management (XManagedNode / ManagedNode)

**Location:** `platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml`

**10 Node Claims (Complete Inventory):**

| Node | Role | Tier | Ray Head | Labels | Taints |
|------|------|------|----------|--------|--------|
| cortex-178-18-250-39 | control-plane | platform | ✗ | tier=platform | (system-managed) |
| cerebrum-157-173-120-200 | control-plane | platform | ✗ | tier=platform | (system-managed) |
| corpus-207-180-206-69 | control-plane | platform | ✗ | tier=platform | (system-managed) |
| nexus-144-91-103-10 | worker | compute | ✗ | tier=compute, ray-cluster=true, nexus-tower=true, apps-ha=true, platform-ha=true, llm-inference role | (none) |
| synapse-161-97-136-251 | worker | compute | ✓ (head) | tier=compute, apps-ha=true, ray-head=true | pool=apps-ha, ray-head=true |
| thalamus-217-76-59-241 | worker | compute | ✗ | tier=compute, platform-ha=true | pool=platform-ha |
| cerebellum-161-97-117-96 | worker | compute | ✓ (head) | tier=compute, platform-ha=true, ray-head=true | pool=platform-ha, ray-head=true |
| quanta-194-163-186-222 | worker | compute | ✓ (head) | tier=compute, ray-head=true, bridge-system=true, dao-system=true | bridge-system=true, dao-system=true, ray-head=true |
| medulla-82-208-20-242 | worker | storage | ✗ | tier=storage | storage-only=true |
| campus-212-47-66-101 | worker | storage | ✗ | tier=storage | storage-only=true |

**What Crossplane Does:**
- Applies labels: `cryptophys.io/tier`, `ray-head`, `ray-cluster`, pool identifiers, role labels
- Applies taints: `ray-head:NoSchedule`, `pool=*:NoSchedule`, `bridge-system:NoSchedule`, `dao-system:NoSchedule`, `storage-only:NoSchedule`
- Monitors for drift: If labels/taints are manually removed, Crossplane reconciles them back

**Patterns Applied:**
- Control-plane nodes: System taints managed by Kubernetes/Talos, Crossplane manages workload labels only
- Ray head nodes: Both labels (`ray-head=true`) and taints (`ray-head=true:NoSchedule`) to force exclusivity
- Pool nodes: Taint per pool (e.g., `pool=apps-ha:NoSchedule`) to block unauthorized workloads
- Storage nodes: `storage-only=true:NoSchedule` to prevent non-storage workloads

### 2. Workload Placement (XWorkloadPlacement / WorkloadPlacement)

**Location:** `platform/infrastructure/crossplane-crs/claims-workload-placement.yaml`

**6 Workload Placement Claims:**

| Workload | Namespace | Kind | Target Node | Purpose |
|----------|-----------|------|-------------|---------|
| cerebrum-core | cerebrum | Deployment | nexus | Core inference engine → nexus-tower node |
| cerebrum-llm | cerebrum | Deployment | nexus | LLM sidecar → nexus-tower node |
| cerebrum-ollama | cerebrum | Deployment | nexus | Ollama runtime → nexus-tower node |
| aide-mesh | aide | RayService | quanta | AIDE Ray head → bridge/dao system node |
| cerebrum-llm | cqls-compute | RayService | synapse | Cerebrum Ray LLM head → apps-ha node |
| mcp-mesh | apps-core | RayService | quanta | MCP Ray head → bridge/dao system node |

**What Crossplane Does:**
- Patches Deployment/RayService with nodeSelector: `cryptophys.io/tier=compute`
- Adds preferred node affinity for specific hostname placement
- For RayService: patches both headGroupSpec and workerGroupSpecs

**Patterns Applied:**
- **Deployments:** Simple nodeSelector + affinity patches
- **RayService heads:** Preferred affinity (not hard requirement) to allow failover if node is down
- **Ray workers:** Inherit ray-cluster label nodeSelector from RayService definition

### 3. Cluster Pools (ClusterPool Definition)

**Location:** `platform/infrastructure/crossplane/cluster-pools.yaml`

**3 Pool Definitions (Experimental - Unified Source of Truth):**

| Pool | Nodes | Namespaces | Taints | Purpose |
|------|-------|-----------|--------|---------|
| apps-ha | synapse, nexus | 11 (aide, cerebrum, apps-core, apps-dash, apps-user, bridge, automation, apps-automation, apps-gateway, navigator, platform-ui) | pool=apps-ha:NoSchedule | Core AI workload cluster |
| platform-ha | cortex, cerebrum, corpus, thalamus, cerebellum | 27 (kube-system, flux-system, cert-manager, vault-system, kyverno-system, ... 22 more) | pool=platform-ha:NoSchedule | Platform infrastructure tier |
| storage-only | campus, medulla | (none) | storage-only=true:NoSchedule | Longhorn storage nodes only |

**Future Integration:**
- ClusterPool will become the single source of truth for both Kyverno namespace allowlists and Crossplane pool membership
- Currently created but not yet integrated into Kyverno policy generation

---

## Flux-Managed Resources (NOT Crossplane)

### Storage Configuration (Longhorn)

**Location:** `platform/infrastructure/storage/longhorn-node-*.yaml` (10 files)

**Managed By:** Flux (HelmRelease → Longhorn CRD sync)

**What Flux Does:**
- Applies `longhorn.io/v1beta2 Node` objects per cluster node
- Configures: `allowScheduling`, `evictionRequested`, disk reservations
- Monitors for drift: If Longhorn Node is manually edited, Flux reconciles it

**Example (campus node, in draining state):**
```yaml
apiVersion: longhorn.io/v1beta2
kind: Node
metadata:
  name: campus-212-47-66-101
spec:
  allowScheduling: false  # ← draining
  evictionRequested: true
  disks:
    - name: default-disk-...
      path: /var/lib/longhorn
      allowScheduling: false
      storageReserved: 16000000000  # 16 GiB
```

**Why Not Crossplane?**
- Longhorn Node is domain-specific storage config (belongs in storage layer)
- Flux owns HelmRelease for Longhorn → natural home for Node objects
- Simpler operational model: storage team owns longhorn-node-*.yaml files

**Deviation:** Phase 2 (moving Longhorn to Crossplane) was attempted but reverted due to schema complexity (disks type mismatch). Current state is stable.

---

## Manual / Unmanaged Resources

### None (0 Exceptions)

**Principle:** ALL node-level infrastructure must originate from git.

No manually created:
- Node labels (all via Crossplane ManagedNode claims)
- Node taints (all via Crossplane ManagedNode claims)
- Pod nodeSelectors (all via Crossplane WorkloadPlacement claims)
- Longhorn Node configs (all via Flux longhorn-node-*.yaml)

---

## Deleted / Deprecated

### 1. ~~node-labeler-job~~ (Replaced by Crossplane)

**File:** ~~`platform/infrastructure/scheduling/node-labeler-job.yaml`~~

**Reason for Deletion:** One-shot bootstrap Job lacked continuous reconciliation. Nodes drifted after reprovisioning.

**Replaced By:** Crossplane ManagedNode claims (same labels, continuous reconciliation)

### 2. ~~claims-platform-nodes.yaml (stale duplicate)~~ (Deleted)

**File:** ~~`platform/infrastructure/crossplane/claims-platform-nodes.yaml`~~

**Reason for Deletion:** File was not included in any kustomization. ManagedNode claims are in `platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml`.

---

## Label & Taint Drift History

### Ghost Labels (Identified & Fixed - Commit 6f3009f)

**What:** Nodes had labels with no declared source (found via kubectl inspect vs Crossplane claims).

**Examples:**
- nexus: `workload.cryptophys.work/apps=true` (not in node-labeler-job)
- synapse: `cryptophys.io/node-type=synapse-head` (no source)
- thalamus: `ray-head=true` (erroneous for platform-ha node)

**Fix:** Updated all 10 ManagedNode claims to include missing workload labels:
```yaml
customLabels:
  workload.cryptophys.work/apps: "true"
  workload.cryptophys.work/apps-core: "true"
  workload.cryptophys.work/llm: "true"  # etc.
```

**Prevention:** Crossplane continuously reconciles, any future label drift is auto-corrected.

### Taint Mismatch (Identified & Fixed - Commit 6f3009f)

**What:** thalamus had `ray-head=true:NoSchedule` taint but is a platform-ha node (should not run Ray heads).

**Fix:** Removed `ray-head=true` taint from thalamus ManagedNode claim.

**Prevention:** Claims are reviewed before apply, Crossplane enforces declared state.

---

## Verification Procedure

### Quick Health Check (5 minutes)

```bash
# 1. All nodes synced
kubectl get managednode -n crossplane-system -o wide
# Expected: STATUS=Synced, READY=True for all 10

# 2. All workload placements synced
kubectl get workloadplacement -n crossplane-system -o wide
# Expected: STATUS=Synced, READY=True for all 6

# 3. Label integrity (spot check)
kubectl get node nexus-144-91-103-10 -o jsonpath='{.metadata.labels}' | jq .
# Expected: tier=compute, ray-cluster=true, nexus-tower=true, etc.

# 4. Taint integrity (spot check)
kubectl get node synapse-161-97-136-251 -o jsonpath='{.spec.taints}' | jq .
# Expected: [{key: ray-head, value: "true", effect: NoSchedule}, {key: pool, value: apps-ha, effect: NoSchedule}]
```

### Full Audit (30 minutes)

```bash
# 1. Export all node labels from live cluster
kubectl get nodes -o json | jq '.items[] | {name: .metadata.name, labels: .metadata.labels, taints: .spec.taints}' > /tmp/live-nodes.json

# 2. Compare against Crossplane claims
# (Manual inspection: do live labels match claimed labels?)

# 3. Check for "ghost" labels (in live cluster but not in claims)
# Example: grep for workload.cryptophys.work, ray-head, etc. in all nodes

# 4. Verify Longhorn Node configs
kubectl get nodes.longhorn.io -n longhorn-system -o wide
# Expected: 10 nodes, appropriate scheduling/eviction state
```

### Reconciliation Force (if needed)

```bash
# Force Crossplane to immediately reconcile (not waiting for sync interval)
kubectl patch managednode cortex-178-18-250-39 -n crossplane-system -p '{"metadata":{"annotations":{"crossplane.io/external-name":"cortex-178-18-250-39"}}}' --type=merge

# Force Flux to immediately reconcile (not waiting for 10m interval)
flux reconcile helmrelease longhorn -n flux-system
```

---

## Operational Patterns

### Pattern 1: Add a New Compute Node

1. **Provision via Talos:** `talosctl apply-config --nodes 10.8.0.11 ...`
2. **Add ManagedNode claim** to `platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml`
3. **Commit & push:** `git add ... && git commit -m "add(compute-node): atlas-***"`
4. **Verify:** `kubectl get managednode <new-node> -n crossplane-system -w` (wait for SYNCED=True)
5. **Monitor:** Check Longhorn, Cilium, metric scraping for new node

### Pattern 2: Change Node Pool (e.g., synapse from apps-ha to platform-ha)

1. **Update ManagedNode claim:** Change `taints[pool]` from `apps-ha` to `platform-ha`
2. **Commit & push:** Auto-syncs within 5 minutes
3. **Cordon old workloads:** Node will reject new pods, Deployments will scale to other nodes
4. **Verify:** `kubectl describe node synapse-... | grep Taints`

### Pattern 3: Pin a Workload to Specific Node

1. **Create WorkloadPlacement claim** in `platform/infrastructure/crossplane-crs/claims-workload-placement.yaml`
2. **Specify:** `targetWorkload.name`, `targetWorkload.namespace`, `placement.preferredNode`
3. **For RayService:** Set `kind: RayService` (Crossplane will patch rayClusterConfig.headGroupSpec)
4. **Commit & push:** Deployment/RayService gets nodeAffinity patch within 5 minutes

### Pattern 4: Drain a Node (e.g., campus for maintenance)

1. **Update ManagedNode claim:** Set `customLabels.draining: "true"` (or update longhorn-node-*.yaml)
2. **Cordon in Talos:** `talosctl  -n 10.8.0.5 health`
3. **Wait for PVCs to migrate:** Monitor `kubectl get pvc -A --sort-by=.spec.volumeName`
4. **Verify empty:** `kubectl get pods --all-namespaces -o wide | grep campus-*`
5. **Shut down:** `talosctl shutdown -n 10.8.0.5`

---

## Known Limitations & Future Work

### 1. ClusterPool Integration (Planned)

**Current:** ClusterPool definitions exist but not yet integrated into Kyverno policies.

**Future:** Kyverno will consume ClusterPool.spec.namespaces to auto-generate namespace allowlists, eliminating current hardcoded lists.

### 2. RayService Composition (In Progress)

**Current:** RayService WorkloadPlacement partially working (head placement via preferred affinity).

**Future:** Support for worker group scaling hints and automatic worker tolerance injection.

### 3. Longhorn Migration (Deferred)

**Current:** Longhorn Node objects managed by Flux (longhorn-node-*.yaml files).

**Future:** Migrate to Crossplane once schema complexities resolved. Phase 2 attempted but deferred.

### 4. Static Node Pool Taints (Planned)

**Current:** Pool taints (e.g., `pool=apps-ha:NoSchedule`) are manually maintained in claims.

**Future:** Auto-generate taints from ClusterPool definitions.

---

## Troubleshooting Guide

### Symptom: Pod CrashLoops, stuck in Pending

**Check 1:** Node has required taint?
```bash
kubectl get node <node-name> -o jsonpath='{.spec.taints}' | jq '.[].key'
# If pod tolerates ray-head but node has pool=apps-ha taint, pod can't schedule
```

**Check 2:** ManagedNode claim exists?
```bash
kubectl get managednode -n crossplane-system <node-name>
# If STATUS=NotReady, Crossplane can't reach provider
```

**Check 3:** WorkloadPlacement applied?
```bash
kubectl get workloadplacement -n crossplane-system <workload>-placement
# If STATUS=Syncing, Crossplane is patching the manifest
```

### Symptom: Labels disappear after node restart

**Root Cause:** Node-labeler-job was deleted; only Crossplane manages labels.

**Fix:** Force Crossplane reconciliation:
```bash
kubectl delete managednode <node-name> -n crossplane-system && sleep 5
kubectl get managednode -n crossplane-system  # Auto-recreates from claim
```

### Symptom: Ray head pod running on wrong node

**Check:** WorkloadPlacement claim exists and preferredNode is correct
```bash
kubectl get workloadplacement <name> -n crossplane-system -o yaml
# Verify spec.placement.preferredNode matches intended node
```

**Fix:** Update claim, push to git, Crossplane re-patches within 5 min.

---

## Commits & History

| Commit | Date | Change |
|--------|------|--------|
| 6f3009f | 2026-04-12 | Fix: Add missing workload labels + fix thalamus ray-head issue |
| c1b57d7 | 2026-04-12 | Feat: Create ClusterPool definitions (Option C) |
| 1253d1d | 2026-04-12 | Feat: Implement RayService WorkloadPlacement claims (Option D) |
| (earlier) | ... | Initial Crossplane setup, node claims, workload placement |

---

## References

- **Crossplane Docs:** https://crossplane.io/docs/latest/
- **Kubernetes Taints/Tolerations:** https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/
- **ManagedNode XRD:** `platform/infrastructure/crossplane/definition.yaml`
- **ManagedNode Composition:** `platform/infrastructure/crossplane/composition.yaml`
- **WorkloadPlacement XRD:** `platform/infrastructure/crossplane/workload-placement-definition.yaml`
- **ClusterPool Definition:** `platform/infrastructure/crossplane/cluster-pools.yaml`

---

**Document Owner:** Claude Code  
**Last Reviewed:** 2026-04-12  
**Next Review:** 2026-05-12 (monthly audit)
