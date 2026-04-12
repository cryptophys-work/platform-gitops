# P2: Longhorn Node Configuration Management via Crossplane

**Status:** 🟡 DEFERRED - OPTIONAL  
**Timeline:** 2-4 weeks  
**Complexity:** High (schema challenges)  
**Priority:** LOW (Flux-based management is stable, no urgency to migrate)

---

## Overview

Migrate Longhorn Node configuration from Flux-managed `longhorn-node-*.yaml` files to Crossplane ManagedNode `longhornNode` specification. This is an **optional optimization** — the current Flux approach is working well.

---

## Why Defer?

Phase 1 attempted Longhorn integration and encountered schema complexity:

1. **Schema Mismatch:** Longhorn Node CRD uses `spec.disks[].name: object` but we defined `disks: array[object]` in XRD
2. **Multi-Disk Complexity:** nexus has 2 disks; defining fixed schema for variable count is tricky
3. **Low Urgency:** Flux is managing longhorn-node-*.yaml files reliably (working)

**Decision:** Keep Longhorn Flux-managed; plan P2 as future enhancement if operational needs change.

---

## Phase 2 Goals (If Implemented)

### Goal 1: Unified Node Configuration
Consolidate all node management into single Crossplane interface:
```
ManagedNode (labels + taints + longhorn config) ← Current
├── spec.tier
├── spec.customLabels
├── spec.taints
└── spec.longhornNode  ← NEW (optional)
    ├── allowScheduling
    ├── evictionRequested
    └── disks[]
```

### Goal 2: Single Git Source for All Node State
Currently split:
- Labels/Taints: `platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml`
- Longhorn: `platform/infrastructure/storage/longhorn-node-*.yaml` (10 files)

After P2:
- All: `platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml` (1 file)

### Goal 3: Eliminate Manual Longhorn Node Management
- Current: Edit 10 separate files for node changes
- Future: Edit 1 claim file, Crossplane handles Longhorn sync

---

## Technical Challenges

### Challenge 1: Longhorn Disk Schema

**Actual Longhorn CRD Structure:**
```yaml
spec:
  disks:
    default-disk-080600000000:  # ← Map key is dynamic
      path: /var/lib/longhorn
      allowScheduling: true
      storageReserved: 10000000000
```

**XRD Schema Problem:**
Maps are tricky in Kubernetes schema. Options:
1. Use `additionalProperties: true` (lose type safety)
2. Use fixed keys: `disk0`, `disk1`, `disk2` (works for nexus multi-disk)
3. Use array of objects with `name` field (different from Longhorn's map structure)

**Mitigation:** Use Option 2 for nexus (fixed disk0/disk1), Option 1 for others.

### Challenge 2: Storage Reserved Values

Longhorn uses bytes; different per node:
```
cortex: 20GiB = 21474836480 bytes
campus: 16GiB = 17179869184 bytes (draining)
medulla: 20GiB = 21474836480 bytes (draining)
```

**XRD Definition:** 
```yaml
storageReserved:
  type: integer
  description: "bytes reserved for system (not available to Longhorn)"
```

**Challenge:** Easy to mistype large numbers. Solution: Document conversion formula.

### Challenge 3: Composition Patching

Longhorn Node CRD structure is different from standard K8s Pod templates:
- Longhorn Node: `spec.disks` (map of disk objects)
- Standard: Pods don't have this structure

**Mitigation:** Create separate Composition resource type for Longhorn (like we did for RayService).

---

## Implementation Plan (If Proceeding)

### Phase 2a: Design Longhorn XRD Extension

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xmanagednodes.cryptophys.work
spec:
  # ... existing spec ...
  versions:
  - name: v1alpha1
    schema:
      openAPIV3Schema:
        properties:
          spec:
            properties:
              # ... existing tier, customLabels, taints ...
              longhornNode:
                type: object
                properties:
                  allowScheduling:
                    type: boolean
                    default: true
                  evictionRequested:
                    type: boolean
                    default: false
                  disks:
                    type: object
                    additionalProperties: true  # ← Allows flexible disk names
                    # OR for fixed schema:
                    properties:
                      disk0:  # Primary disk
                        type: object
                        properties:
                          path: { type: string }
                          allowScheduling: { type: boolean }
                          storageReserved: { type: integer }
                      disk1:  # Secondary (for multi-disk nodes like nexus)
                        type: object
                        # ... same as disk0
```

### Phase 2b: Extend Composition for Longhorn

Create second patch resource in composition:
```yaml
- name: patch-longhorn-node
  base:
    apiVersion: kubernetes.crossplane.io/v1alpha1
    kind: Object
    spec:
      forProvider:
        manifest:
          apiVersion: longhorn.io/v1beta2
          kind: Node
          metadata:
            name: <node-name>
          spec:
            allowScheduling: true
            disks: {}
  patches:
  - fromFieldPath: "spec.targetWorkload.name" → manifest.metadata.name
  - fromFieldPath: "spec.longhornNode.allowScheduling" → spec.allowScheduling
  - fromFieldPath: "spec.longhornNode.disks" → spec.disks
```

### Phase 2c: Update Claims

```yaml
apiVersion: cryptophys.work/v1alpha1
kind: ManagedNode
metadata:
  name: nexus-144-91-103-10
spec:
  tier: compute
  customLabels: { ... }
  taints: [ ... ]
  longhornNode:
    allowScheduling: true
    disks:
      disk0:
        path: /var/lib/longhorn
        allowScheduling: true
        storageReserved: 21474836480  # 20 GiB
      disk1:
        path: /var/mnt/longhorn-data
        allowScheduling: true
        storageReserved: 5368709120   # 5 GiB additional
```

### Phase 2d: Delete 10 longhorn-node-*.yaml Files

Once Crossplane is managing Longhorn Node CRDs:
```bash
rm platform/infrastructure/storage/longhorn-node-*.yaml
git add -A
git commit -m "chore(p2): remove Flux-managed longhorn-node files (now Crossplane-managed)"
git push
```

### Phase 2e: Test & Validation

```bash
# Verify Longhorn nodes are created
kubectl get nodes.longhorn.io -n longhorn-system -o wide

# Check allowScheduling and disk configuration
kubectl get nodes.longhorn.io nexus-144-91-103-10 -o yaml | grep -A 20 "spec:"

# Test: Change storageReserved
# 1. Edit claim
# 2. Push to git
# 3. Verify Longhorn Node CRD updated within 5 minutes
```

---

## Cost-Benefit Analysis

### Benefits
- ✅ Unified node management (1 XRD for labels + taints + Longhorn)
- ✅ Single git source (no duplication)
- ✅ Reduced operational files (10 files → 0, consolidated in 1 claim file)
- ✅ Drift detection for Longhorn config

### Costs
- ⚠️ High schema complexity (custom type definitions)
- ⚠️ Testing burden (Longhorn Node validation tricky)
- ⚠️ Multi-disk node handling (nexus special case)
- ⚠️ Implementation time (2-4 weeks)

### ROI Assessment

**Current Pain:** Longhorn is working fine (0 operational incidents)

**Problem Solved by P2:** Theoretical unification + drift detection (not urgent)

**Recommendation:** **DEFER** until:
1. Longhorn drift issues become operational problem, OR
2. Team has spare capacity for "nice to have" improvements

---

## Fallback: Simplified Longhorn Integration

If full schema support is too complex, simpler alternative:

```yaml
longhornNode:
  type: object
  x-kubernetes-preserve-unknown-fields: true  # ← Let Longhorn define schema
```

This allows full Longhorn structure without needing to validate every field, at the cost of losing XRD schema documentation.

**Tradeoff:** Easier implementation but looser validation.

---

## Monitoring & Documentation

### If Proceeding with P2:

1. **Update AUDIT-INVENTORY.md:**
   - Document Longhorn integration strategy
   - List all longhornNode configurations

2. **Update OPERATIONS-RUNBOOK.md:**
   - Add: "Adjust node storage reservation" procedure
   - Add: "Drain node for maintenance" (now involves Crossplane)
   - Add: "Configure multi-disk nodes" (nexus special case)

3. **Update DESIGN-PATTERNS.md:**
   - Add: Longhorn integration pattern
   - Document: why full schema validation vs. `x-kubernetes-preserve-unknown-fields`

---

## Deferred Decision

**For Now:** Keep Phase 2 as **optional future enhancement**. 

**Trigger for Implementing P2:**
- Longhorn drift becomes problem (manual fixes needed)
- Team capacity available for 2-4 week effort
- Schema complexity is resolved in a cleaner way

**If Never Implemented:**
- Flux-based longhorn-node-*.yaml continues working
- No loss of functionality or operational capability
- Trade-off: 10 separate files instead of 1 unified claim file

---

## References

- **Current Longhorn Config:** `platform/infrastructure/storage/longhorn-node-*.yaml` (10 files)
- **Longhorn CRD Spec:** Check live cluster: `kubectl get crd nodes.longhorn.io -o yaml`
- **Phase 1 Attempt:** Previous deferred Longhorn work (hit schema issues)

---

**Status:** DEFERRED - Awaiting operational drivers  
**Contingency:** Flux-based management remains functional  
**Risk if Deferred:** Low (no operational impact)  
**Owner:** Platform team (when capacity available)
