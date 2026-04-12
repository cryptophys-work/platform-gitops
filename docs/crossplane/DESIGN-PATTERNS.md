# Crossplane Infrastructure Design Patterns

Architectural patterns and design decisions for managing Kubernetes node infrastructure via Crossplane.

---

## Overview

Crossplane manages two infrastructure layers:
1. **Node Infrastructure (XManagedNode):** Labels, taints, node-level state
2. **Workload Placement (XWorkloadPlacement):** Pod-to-node affinity and scheduling hints

This document explains the reasoning, trade-offs, and future enhancements.

---

## Pattern 1: Node Tiers with Exclusive Taints

### Design

All cluster nodes belong to one of three tiers:
- **platform** (control-plane nodes): cluster infrastructure, system services
- **compute** (worker nodes): application workloads, Ray clusters
- **storage** (dedicated nodes): Longhorn storage only

Each tier has an identifying label and an optional exclusive taint:

```yaml
# Platform tier node (control-plane)
metadata:
  labels:
    cryptophys.io/tier: platform
spec:
  taints: []  # System-managed, Crossplane does not add taints

# Compute tier node (general workload)
metadata:
  labels:
    cryptophys.io/tier: compute
spec:
  taints: []  # No exclusive taint; pods tolerate by default

# Storage tier node (Longhorn only)
metadata:
  labels:
    cryptophys.io/tier: storage
spec:
  taints:
  - key: cryptophys.io/storage-only
    value: "true"
    effect: NoSchedule
```

### Rationale

- **Label-based selection** is primary (compatible with all pod types)
- **Taints are enforcement** (prevent unauthorized workload migration)
- **No taint on compute tier** reduces operational friction (pods don't need explicit tolerations for general scheduling)
- **Taint on storage tier** prevents non-Longhorn workloads from running there

### Trade-offs

**Pros:**
- Simple tier model (3 options)
- Pod scheduling clear: workload namespace determines allowed tier
- Easy to audit (label shows tier intent)

**Cons:**
- Compute tier is under-specified (any pod can run there unless other taints restrict it)
- Mitigation: Kyverno policies restrict namespaces per node via clusterPool definitions

---

## Pattern 2: Pool-Based Node Grouping

### Design

Beyond tiers, nodes can belong to **pools** (logical subdivisions):
- **apps-ha**: synapse, nexus (core AI workloads)
- **platform-ha**: cortex, cerebrum, corpus, thalamus, cerebellum (platform infra)
- **storage-only**: campus, medulla (storage-only)
- **ray-head**: synapse, cerebellum, quanta (Ray cluster heads)

Pools are enforced via taints:

```yaml
# apps-ha pool node
spec:
  taints:
  - key: cryptophys.io/pool
    value: apps-ha
    effect: NoSchedule

# ray-head pool node (additional taint)
spec:
  taints:
  - key: ray-head
    value: "true"
    effect: NoSchedule
```

Each pool maps to a set of allowed namespaces (defined in ClusterPool).

### Rationale

- **Namespace-pool mapping** ensures workload isolation (apps can't leak to platform infra)
- **Taints enforce boundaries** (rogue toleration in pod spec won't break policy)
- **Kyverno policies read ClusterPool** to auto-generate namespace allowlists (future)

### Trade-offs

**Pros:**
- Explicit boundaries between workload types
- Easy to scale: add node → update pool claim → auto-synced
- Audit trail: every workload's allowed nodes visible in git

**Cons:**
- Requires pod to tolerate multiple taints (apps-ha pool + potential ray-head taint)
- ClusterPool is declarative but not yet auto-integrated into Kyverno
- Mitigation: Manual Kyverno policy alignment for now; automation planned

---

## Pattern 3: Label-Based Workload Placement

### Design

Workloads are placed via **WorkloadPlacement claims**, not hardcoded nodeSelectors:

```yaml
# Instead of:
# deployment.spec.template.spec.nodeSelector:
#   kubernetes.io/hostname: nexus-144-91-103-10

# Use:
apiVersion: cryptophys.work/v1alpha1
kind: WorkloadPlacement
metadata:
  name: cerebrum-core
spec:
  targetWorkload:
    kind: Deployment
    name: cerebrum-core
    namespace: cerebrum
  placement:
    tier: compute
    preferredNode: nexus-144-91-103-10
```

Crossplane patches the Deployment with nodeSelector + nodeAffinity.

### Rationale

- **Decouples workload from hostname** (apps-gitops doesn't know node IPs)
- **Single source of truth** (all placement decisions in platform-gitops)
- **Enables failover** (preferredNode is soft, not hard requirement)
- **Versioned in git** (placement decisions auditable)

### Trade-offs

**Pros:**
- Apps repo doesn't hardcode node hostnames
- Easy to understand placement intent
- Automatic failover if preferred node is down

**Cons:**
- Crossplane must know workload location (namespace, name, kind)
- Composition must support each workload kind (Deployment, RayService, StatefulSet)
- Workload must still exist before claim (can't pre-declare)
- Mitigation: Claims are lightweight; composition uses patches not replacements

---

## Pattern 4: Ray Head Affinity (Preferred, Not Required)

### Design

Ray head pods get **preferred node affinity**, not hard requirement:

```yaml
# WorkloadPlacement translates to:
spec:
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
          - key: kubernetes.io/hostname
            operator: In
            values:
            - quanta-194-163-186-222
```

NOT:

```yaml
# (this would block scheduling if preferred node is down)
requiredDuringSchedulingIgnoredDuringExecution:
- ...
```

### Rationale

- **Fault tolerance** (Ray head doesn't block if preferred node is unavailable)
- **Load balancing** (Can spread multiple Ray heads across multiple nodes if needed)
- **Graceful degradation** (Cluster remains operational even if preferred node is rebooting)

### Trade-offs

**Pros:**
- Cluster stays operational during node maintenance
- Ray can auto-scale heads if preferred node is overloaded

**Cons:**
- Ray head may move between nodes (affects state, caching)
- Requires Ray service restart to pick up new node (stateful workload)
- Mitigation: Update NodeAffinity affinity weight or use StatefulSets with persistent volumes if state is critical

---

## Pattern 5: Composition-Based Patching (Not Replacement)

### Design

Crossplane compositions use **patch resources**, not replacement:

```yaml
# Composition patches existing Deployment
resources:
- name: patch-deployment-placement
  base:
    apiVersion: kubernetes.crossplane.io/v1alpha1
    kind: Object  # Kubernetes object wrapper
    spec:
      forProvider:
        manifest:
          apiVersion: apps/v1
          kind: Deployment  # Patch target
          metadata:
            name: "" # Patched from claim
          spec:
            template:
              spec:
                nodeSelector:
                  cryptophys.io/tier: compute  # Applied by patch

patches:
- fromFieldPath: "spec.targetWorkload.name"
  toFieldPath: "spec.forProvider.manifest.metadata.name"
# ... more patches
```

This means:
- Deployment already exists in cluster (created by ArgoCD/Flux)
- Crossplane discovers and patches it
- If claim is deleted, Deployment remains (no orphaning)

### Rationale

- **Non-destructive** (Crossplane observes and enhances, doesn't replace)
- **Separation of concerns** (ArgoCD manages Deployment, Crossplane manages placement)
- **No conflicts** (multiple controllers can patch same resource safely)

### Trade-offs

**Pros:**
- Crossplane doesn't own the Deployment lifecycle
- Easy to debug (patch is explicit, not hidden in Composition)
- Can add/remove placement without redeploying workload

**Cons:**
- Requires target workload to exist first (can't declare both in git simultaneously)
- Patch failures are silent if target doesn't exist
- Mitigation: Always verify WorkloadPlacement status is Synced

---

## Pattern 6: Optional / Soft-Fail Patches

### Design

Some patches are optional (don't fail if field doesn't exist):

```yaml
patches:
# Required: target workload name
- fromFieldPath: "spec.targetWorkload.name"
  toFieldPath: "spec.forProvider.manifest.metadata.name"

# Optional: preferred node (may not be specified)
- fromFieldPath: "spec.placement.preferredNode"
  toFieldPath: "spec.forProvider.manifest.spec.affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].preference.matchExpressions[0].values[0]"
  policy:
    fromFieldPath: Optional  # Don't fail if not present
```

### Rationale

- **Flexible claims** (preferredNode can be omitted for any-node scheduling)
- **Incremental adoption** (start with tier-only, add preferredNode later)
- **Graceful degradation** (missing optional field doesn't block reconciliation)

### Trade-offs

**Pros:**
- Claims are simpler (only required fields)
- Easy to extend (add optional fields without changing existing claims)

**Cons:**
- Composition gets complex (many conditional patches)
- Hard to debug (missing field silently ignored)
- Mitigation: Document which fields are optional, validate in CI

---

## Pattern 7: ClusterPool as Unified Source of Truth

### Design (Planned)

ClusterPool definition unifies node pools and namespace allowlists:

```yaml
apiVersion: cryptophys.work/v1alpha1
kind: ClusterPool
metadata:
  name: apps-ha
spec:
  description: "Apps HA workload pool"
  nodes:
  - synapse-161-97-136-251
  - nexus-144-91-103-10
  namespaces:
  - aide
  - cerebrum
  - apps-core
  - apps-dash
  - # ... 7 more namespaces
```

Future integrations:
- **Kyverno:** Generate namespace allowlist policies from ClusterPool.spec.namespaces
- **Crossplane:** Auto-generate taint values from ClusterPool.spec.nodes
- **Audit:** Generate RBAC and ABAC rules per pool

### Rationale

- **Single source of truth** (no duplicated namespace lists in Kyverno policies)
- **Automated policy generation** (reduce manual config, reduce errors)
- **Audit trail** (all pool membership decisions in git)

### Trade-offs

**Pros:**
- Eliminates duplication between Crossplane claims and Kyverno policies
- Easy to add namespace to pool (update 1 file, auto-synced everywhere)

**Cons:**
- Requires Kyverno integration (not yet implemented)
- Breaking change to existing policies (migration path needed)
- Mitigation: Create ClusterPool now, integrate gradually with Kyverno

---

## Pattern 8: Tiered Placement (Tier → Pool → Node)

### Design

Placement hierarchy:
1. **Tier** (required): platform, compute, storage
   - Broad workload category
   - Enforced via label

2. **Pool** (optional): apps-ha, platform-ha, storage-only
   - Workload subdivision
   - Enforced via taint

3. **Preferred Node** (optional): specific hostname
   - Fine-grained placement
   - Soft constraint (preferred, not required)

```yaml
# Hierarchy in WorkloadPlacement
spec:
  placement:
    tier: compute          # Level 1: tier selector
    # (level 2: pool implicit via pod tolerations)
    preferredNode: nexus-144-91-103-10  # Level 3: specific node
```

### Rationale

- **Progressive refinement** (start coarse, tighten if needed)
- **Flexibility** (tier alone is sufficient for most workloads)
- **Compatibility** (works with Kyverno namespace-pool mapping)

### Trade-offs

**Pros:**
- Matches Kyverno's pod→namespace→pool model
- Supports both simple and complex placements

**Cons:**
- Three levels of indirection (confusing for operators)
- Requires documentation (clear naming helps)
- Mitigation: Provide templates and examples

---

## Pattern 9: Flux + Crossplane Separation of Concerns

### Design

- **Flux** owns: HelmRelease, Kustomizations, Git sync, source repos
- **Crossplane** owns: Node labels, taints, workload placement

**Example:**

```
Git (platform-gitops)
├── Flux (40-flux-controller)
│   └── Manages: HelmRelease longhorn, HelmRelease crossplane
├── Crossplane (41-crossplane-operator)
│   └── Manages: ManagedNode, WorkloadPlacement, XRD, Composition
└── Storage (30-storage)
    ├── longhorn-node-*.yaml (Flux-managed)
    └── (Crossplane integration: planned Phase 2)
```

Workflow:
1. Flux applies HelmRelease → installs Crossplane
2. Crossplane applies XRD, Composition → enables claims
3. Crossplane applies ManagedNode claims → labels/taints nodes
4. Flux applies HelmReleases → deploys apps
5. Crossplane applies WorkloadPlacement → pins workloads to nodes

### Rationale

- **Layered architecture** (each tool does one thing well)
- **Clear ownership** (Flux = deployment, Crossplane = infrastructure)
- **Parallel operation** (Flux and Crossplane sync independently)

### Trade-offs

**Pros:**
- Each tool has clear responsibility
- Easy to troubleshoot (know which tool owns which resource)
- Can swap out tools (e.g., replace Flux with ArgoCD for some resources)

**Cons:**
- Two sync loops (Flux + Crossplane)
- Potential race conditions (Flux deploys app, Crossplane patches it)
- Mitigation: Crossplane patches are idempotent; races don't cause issues

---

## Anti-Patterns to Avoid

### ❌ Hardcoded Node Hostnames in Pod Specs

```yaml
# BAD: Hostname tightly couples app to infrastructure
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cerebrum-core
spec:
  template:
    spec:
      nodeSelector:
        kubernetes.io/hostname: nexus-144-91-103-10
```

**Why:** If nexus goes down or is replaced, deployment breaks.

**Use Instead:** WorkloadPlacement claims (soft affinity) or tier-based selection.

---

### ❌ Manual Label Maintenance

```bash
# BAD: Label applied manually, no drift detection
kubectl label node nexus-144-91-103-10 ray-cluster=true
```

**Why:** Manual labels disappear on node restart; drift is hard to detect.

**Use Instead:** ManagedNode claims (Crossplane reconciles continuously).

---

### ❌ Mixing Kyverno Policy Namespaces Across Files

```yaml
# BAD: namespace allowlist split between kyverno-policy.yaml and clusterPolicy2.yaml
# (maintainer doesn't know all allowed namespaces without reading both files)

# In file 1:
namespaces:
- apps-core
- apps-dash

# In file 2:
namespaces:
- apps-user
- apps-automation
```

**Why:** Hard to maintain; easy to orphan or duplicate namespaces.

**Use Instead:** ClusterPool unifies all namespaces for a pool.

---

### ❌ Required Node Affinity for Stateless Services

```yaml
# BAD: Hard requirement blocks failover
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/hostname
            operator: In
            values:
            - nexus-144-91-103-10
```

**Why:** If nexus goes down, pods can't reschedule anywhere.

**Use Instead:** `preferredDuringSchedulingIgnoredDuringExecution` (soft preference).

---

### ❌ Crossplane Managing Workload Deployments

```yaml
# BAD: Crossplane owns entire Deployment (recreates on changes)
apiVersion: cryptophys.work/v1alpha1
kind: MyDeploymentClaim
spec:
  image: my-app:v1.0
  # ... full deployment spec
```

**Why:** Crossplane and ArgoCD conflict on ownership.

**Use Instead:** ArgoCD/Flux manages Deployment, Crossplane patches placement only.

---

## Pattern 10: ClusterPool-Driven Kyverno Policy Generation

### Design

ClusterPool definitions drive namespace labels, which drive Kyverno policies:

```
ClusterPool (spec.namespaces list)
   ↓ (defines membership)
Namespace Labels (cryptophys.io/pool: {pool-name})
   ↓ (matched by policies)
Kyverno Policies (namespaceSelector matches labels)
   ↓ (injects/restricts)
Pod Tolerations / Pod Restrictions
```

**Example Flow:**

1. **ClusterPool defines pool membership:**
   ```yaml
   apiVersion: cryptophys.work/v1alpha1
   kind: ClusterPool
   metadata:
     name: apps-ha
   spec:
     nodes:
     - synapse-161-97-136-251
     - nexus-144-91-103-10
     namespaces:  # ← Source of truth
     - aide
     - cerebrum
     - apps-core
     - apps-dash
   ```

2. **Namespace manifests include pool label:**
   ```yaml
   apiVersion: v1
   kind: Namespace
   metadata:
     name: aide
     labels:
       cryptophys.io/pool: apps-ha  # ← Driven by ClusterPool
   ```

3. **Kyverno policies match on label (not hardcoded lists):**
   ```yaml
   apiVersion: kyverno.io/v1
   kind: ClusterPolicy
   metadata:
     name: mutate-pool-tolerations-apps-ha
   spec:
     rules:
     - match:
         resources:
           namespaceSelector:
             matchLabels:
               cryptophys.io/pool: apps-ha  # ← Dynamic matching
       mutate:
         patchStrategicMerge:
           spec:
             tolerations:
             - key: cryptophys.io/pool
               value: apps-ha
   ```

4. **Result: Pod tolerations auto-injected:**
   ```bash
   kubectl get pod <any-pod> -n aide -o yaml | grep tolerations
   # Shows: cryptophys.io/pool: apps-ha toleration
   ```

### Rationale

**Single Source of Truth:** ClusterPool is the only place pool membership is defined
- Add namespace to pool: update ClusterPool + label namespace manifest
- Remove: edit ClusterPool, update namespace label

**Dynamic:** Adding namespace to pool = label it → Kyverno auto-applies
- No policy edits required
- Policies apply within seconds

**Audit Trail:** All pool membership decisions tracked in git
- Changes visible in git log
- Reversible via git revert
- Compliance-friendly (who changed what, when, why)

**No Duplication:** Policies read labels, not hardcoded lists
- Prevents divergence between ClusterPool and policies
- Reduces merge conflicts
- Easier to maintain long-term

### Trade-offs

**Pros:**
- Simplifies policy maintenance (one source, not three separate lists)
- Eliminates hardcoded namespace lists (30+ namespaces no longer scattered)
- Easy onboarding (label namespace → done)
- Dynamic (changes reflect immediately)

**Cons:**
- Requires discipline: namespace labels must match ClusterPool (no divergence)
- Debugging: need to check both ClusterPool and namespace labels
- Initial migration effort (label 40+ existing namespaces)

### Implementation (Completed: Phase 1)

**Phase 1a:** ✅ Labeled 44 namespaces with cryptophys.io/pool
- All existing namespaces now have correct pool labels
- Audit trail in git commits

**Phase 1b:** ✅ Created label-based Kyverno policies
- mutate-pool-tolerations-apps-ha
- mutate-pool-tolerations-platform-ha
- deny-storage-only-pods
- All use matchLabels instead of hardcoded namespace lists

**Phase 1c:** ⏳ Testing (partial - API timeouts)
- ✅ apps-ha toleration injection verified working
- ⏳ Platform-ha and storage-only tests pending (API stability)

**Phase 1d:** ✅ Refactored existing policies
- nexus-placement-policy.yaml mutate rules now use labels
- Removed 50+ lines of hardcoded namespace lists
- Old deny policies kept as secondary defense layer

**Phase 1e:** ✅ Updated documentation
- OPERATIONS-RUNBOOK.md: added namespace pool management procedures
- DESIGN-PATTERNS.md: this pattern
- AUDIT-INVENTORY.md: updated Kyverno section

### When to Use

- Whenever policy rules apply per-pool (taints, node placement, resource limits)
- Ideal for: Toleration injection, namespace isolation, workload affinity
- Not suitable for: Arbitrary policy logic that spans pools

### Related Patterns

- **Pattern 1:** Node Tiers with Exclusive Taints (what the pools map to)
- **Pattern 3:** Workload-Specific Taints & Tolerations (used together)
- **Pattern 8:** ClusterPool-Driven Node Provisioning (complementary)

### Links

- ClusterPool definitions: `platform/infrastructure/crossplane/cluster-pools.yaml`
- Kyverno policies: `platform/infrastructure/policy/cluster-pool-*.yaml`
- Namespace manifests: `platform-gitops/platform/infrastructure/namespaces/`
- Operations guide: [Namespace Pool Management](OPERATIONS-RUNBOOK.md#namespace-pool-management-p1-clusterpool-kyverno-integration)

---

## Future Enhancements

### 1. Auto-Generated Kyverno Policies from ClusterPool

```yaml
# Planned: ClusterPool drives Kyverno policy generation
apiVersion: cryptophys.work/v1alpha1
kind: ClusterPool
metadata:
  name: apps-ha
spec:
  namespaces:
  - aide
  - cerebrum
  # ...

# Auto-generates:
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: apps-ha-namespace-allowlist
rules:
- match:
    resources:
      namespaceSelector:
        matchLabels:
          pool: apps-ha
  validate:
    pattern:
      spec:
        nodeSelector:
          cryptophys.io/tier: compute
```

### 2. RayService Auto-Tolerations

```yaml
# Planned: Crossplane auto-injects tolerations for RayService heads

# Currently: manual tolerations in RayService
spec:
  rayClusterConfig:
    headGroupSpec:
      template:
        spec:
          tolerations:
          - key: ray-head
            value: "true"
            effect: NoSchedule

# Future: Crossplane adds tolerations from ClusterPool
```

### 3. Longhorn Node Integration

```yaml
# Planned: Crossplane manages Longhorn Node configs (Phase 2)

apiVersion: cryptophys.work/v1alpha1
kind: ManagedNode
metadata:
  name: nexus-144-91-103-10
spec:
  tier: compute
  longhornNode:
    allowScheduling: true
    storageReserved: 20000000000  # 20 GiB
    disks:
    - name: default-disk
      path: /var/lib/longhorn
      allowScheduling: true
```

---

## References

- XManagedNode XRD: `platform/infrastructure/crossplane/definition.yaml`
- ManagedNode Composition: `platform/infrastructure/crossplane/composition.yaml`
- ManagedNode Claims: `platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml`
- WorkloadPlacement XRD: `platform/infrastructure/crossplane/workload-placement-definition.yaml`
- WorkloadPlacement Composition: `platform/infrastructure/crossplane/workload-placement-composition.yaml`
- ClusterPool Definition: `platform/infrastructure/crossplane/cluster-pools.yaml`

---

**Document Owner:** Claude Code  
**Last Updated:** 2026-04-12  
**Next Review:** 2026-05-12
