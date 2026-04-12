# P3: Documentation Updates for Phase 2 Completion

**Status:** 🟡 ONGOING (parallel with P0, P1, P2)  
**Timeline:** Continuous throughout phases  
**Complexity:** Low (content updates, no code changes)

---

## Overview

As P0, P1, and P2 complete, update operational documentation to reflect new infrastructure state and procedures.

**Philosophy:** Keep docs in sync with implementation. Update docs **as you implement**, not after.

---

## P3 Tracking: Documentation Updates by Phase

### ✅ Completed (Phase 1 - Done)

- [x] PROJECT-SUMMARY.md — Project overview
- [x] AUDIT-INVENTORY.md — Resource inventory
- [x] DESIGN-PATTERNS.md — Architecture decisions
- [x] TESTING-VALIDATION.md — Test procedures
- [x] INTEGRATION-TEST-REPORT.md — Test results
- [x] P0-API-RATE-LIMIT-ANALYSIS.md — API rate limit findings
- [x] P1-KYVERNO-INTEGRATION-GUIDE.md — Kyverno integration steps
- [x] P2-LONGHORN-INTEGRATION-GUIDE.md — Longhorn optional enhancement

**Total:** 8 docs created (2,963+ lines)

---

### 🟡 In Progress (P0 - Monitoring)

**File:** OPERATIONS-RUNBOOK.md

**Updates Needed:**
- [ ] Add section: "Monitor Crossplane API Rate Limits"
- [ ] Procedure: Check WorkloadPlacement READY status
- [ ] Procedure: Force Crossplane reconciliation (if needed)
- [ ] Workaround: Deployment patches blocked (temporary)

**Expected Completion:** When API rate limits resolve

---

### 🟡 In Progress (P1 - Kyverno Integration)

**Files to Update:**

#### OPERATIONS-RUNBOOK.md

**Add New Procedure:**
```markdown
### Add a Namespace to a Pool

**Objective:** Assign a new namespace to a ClusterPool (apps-ha, platform-ha, or storage-only).

**Steps:**

1. Edit namespace YAML:
   ```yaml
   apiVersion: v1
   kind: Namespace
   metadata:
     name: my-new-app
     labels:
       cryptophys.io/pool: apps-ha  # ← Choose appropriate pool
   ```

2. Apply to cluster:
   ```bash
   kubectl apply -f namespace.yaml
   ```

3. Verify Kyverno policies applied:
   ```bash
   kubectl get pod <test-pod> -n my-new-app -o yaml | grep cryptophys.io/pool
   ```
   **Expected:** Tol eration with pool value injected

**Related:**
- ClusterPool definitions: `cluster-pools.yaml`
- Kyverno policies: `policy/cluster-pool-toleration-injection.yaml`
```

**Update Existing Procedure:**
- "Change Node Pool" → Add note: "Kyverno auto-adjusts namespace tolerations"

**Add Section:**
```markdown
### Troubleshoot Kyverno Policy Issues

If namespace tolerations are not injected:

1. **Verify namespace label:**
   ```bash
   kubectl get ns <name> -o yaml | grep cryptophys.io/pool
   ```

2. **Check policy exists:**
   ```bash
   kubectl get clusterpolicy | grep pool
   ```

3. **Check policy matches:**
   ```bash
   kubectl get clusterpolicy mutate-pool-tolerations-apps-ha -o yaml | grep -A 10 namespaceSelector
   ```

4. **Recreate pod:**
   ```bash
   kubectl delete pod <name> -n <ns>  # Pod recreated with new tolerations
   ```
```

#### AUDIT-INVENTORY.md

**Update Section:** "Kyverno Policies"

**Before:**
```
### Kyverno Policies

10 hardcoded namespace lists scattered across 5 policy files.
```

**After:**
```
### Kyverno Policies

Pool-Based Toleration Injection (ClusterPool-driven):
- mutate-pool-tolerations-apps-ha — Inject apps-ha taint toleration
- mutate-pool-tolerations-platform-ha — Inject platform-ha taint toleration
- deny-storage-only-pods — Block workload pods in storage-only pool

All policies driven by namespace labels (cryptophys.io/pool).
No hardcoded namespace lists.

Integration: ClusterPool → Namespace labels → Kyverno policies

Benefits:
- Single source of truth (ClusterPool definitions)
- Dynamic membership (label namespace → policy auto-applies)
- Audit trail (all decisions in git)
```

#### DESIGN-PATTERNS.md

**Add New Pattern:**

```markdown
### Pattern 10: ClusterPool-Driven Policy Generation

**Design**

ClusterPool definitions feed namespace labels, which drive Kyverno policies:

```
ClusterPool (spec.namespaces list)
   ↓
Namespace Labels (cryptophys.io/pool: {pool-name})
   ↓
Kyverno Policies (namespaceSelector matches labels)
   ↓
Taint Injection / Pod Restrictions
```

**Rationale**

- **Single Source of Truth:** ClusterPool is the only place pool membership is defined
- **Dynamic:** Adding namespace to pool = label it → Kyverno auto-applies
- **Audit Trail:** All pool membership decisions tracked in git
- **No Duplication:** Policies read labels, not hardcoded lists

**Trade-offs**

**Pros:**
- Simplifies policy maintenance
- Eliminates hardcoded namespace lists
- Easy onboarding (label namespace → done)

**Cons:**
- Requires discipline: namespace labels must match ClusterPool
- Debugging: need to check both ClusterPool and namespace labels

**Implementation**

1. ClusterPool defines desired namespaces: `spec.namespaces: [aide, cerebrum, ...]`
2. Namespace manifest includes label: `cryptophys.io/pool: apps-ha`
3. Kyverno policy selector matches label: `namespaceSelector.matchLabels: cryptophys.io/pool: apps-ha`
4. Policy injects pool-specific tolerations

**When to Use**

- Whenever policy rules apply per-pool (taints, node placement, resource limits)
- Ideal for: Toleration injection, namespace isolation, workload affinity
- Not suitable for: Arbitrary policy logic that spans pools
```

---

### 🟡 If Implemented (P2 - Longhorn Integration)

**Files to Update** (only if P2 is implemented):

#### AUDIT-INVENTORY.md

**Update Section:** "Storage Configuration (Longhorn)"

**Before:**
```
### Storage Configuration (Longhorn)

Location: platform/infrastructure/storage/longhorn-node-*.yaml (10 files)
Managed By: Flux
```

**After:**
```
### Storage Configuration (Longhorn)

Managed By: Crossplane (unified in ManagedNode)
Location: platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml

Each ManagedNode claim includes:
  spec.longhornNode:
    allowScheduling: bool
    disks:
      disk0: {path, allowScheduling, storageReserved}
      disk1: {path, allowScheduling, storageReserved}  # (nexus multi-disk only)
```

#### OPERATIONS-RUNBOOK.md

**Add New Procedure:**

```markdown
### Adjust Node Storage Reservation

**Objective:** Change how much storage is reserved (unavailable to Longhorn).

**Example:** Campus node has 16 GiB reserved; reduce to 14 GiB.

**Steps:**

1. Find node's storage reservation:
   ```bash
   grep -A 10 "name: campus-212" claims-platform-nodes.yaml | grep storageReserved
   ```

2. Calculate new value in bytes:
   ```
   New reservation: 14 GiB = 15,032,705,024 bytes
   ```

3. Update claim:
   ```yaml
   spec:
     longhornNode:
       disks:
         disk0:
           storageReserved: 15032705024  # ← Changed
   ```

4. Commit and push:
   ```bash
   git add platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml
   git commit -m "chore: adjust campus storage reservation to 14 GiB"
   git push origin main
   ```

5. Verify Longhorn Node CRD updated:
   ```bash
   kubectl get nodes.longhorn.io campus-212-47-66-101 -o yaml | grep storageReserved
   ```
```

#### DESIGN-PATTERNS.md

**Add New Pattern:**

```markdown
### Pattern 11: Unified Node Infrastructure (ManagedNode)

**Design**

Single Crossplane resource manages all node-level infrastructure:

```
ManagedNode
  ├── spec.tier — Node tier (platform/compute/storage)
  ├── spec.customLabels — All node labels (role, workload domain)
  ├── spec.taints — Node taints (pool identity, ray-head exclusivity)
  └── spec.longhornNode — Storage configuration
      └── disks[] — Per-disk settings (reservation, scheduling)
```

**Rationale**

- **Unified Source:** All node config in one place (not scattered across files)
- **Consistent:** All nodes managed same way (no special cases)
- **Scalable:** Add node = one claim entry (with label, taint, storage)

**Trade-offs**

**Pros:**
- Reduces operational file count (10 longhorn files → 0)
- Consistent workflow (all node changes via claims)
- Single git audit trail

**Cons:**
- Larger claim files (verbose, but clear intent)
- Schema complexity (handling multi-disk nodes)
```

---

### 📋 Checklist for P3

**Every time you complete a phase task:**

- [ ] Update AUDIT-INVENTORY.md with new state
- [ ] Update OPERATIONS-RUNBOOK.md with new procedures
- [ ] Update DESIGN-PATTERNS.md with architectural implications
- [ ] Add section to TESTING-VALIDATION.md for new features

**Trigger:** After each phase (P0, P1, P2) completes

---

## Documentation Maintenance Principles

### 1. Keep Docs in Sync with Code

**Rule:** If you change code, update docs immediately (same commit).

**Example:**
```bash
# Don't do this:
git commit -m "feat: implement ClusterPool-Kyverno integration"  # Incomplete

# Do this:
git add code-changes.yaml docs-updates.md
git commit -m "feat: implement ClusterPool-Kyverno integration + docs"
```

### 2. Documentation is Runnable

**Rule:** Every procedure in the runbook must be tested before committing.

**Example:**
```bash
# Before committing "Add namespace to pool" procedure:
# 1. Create test namespace
# 2. Label it with pool
# 3. Verify Kyverno policy applies
# 4. Document exactly what you did
# 5. Commit procedure with evidence of testing
```

### 3. Cross-Reference Everything

**Rule:** Each document links to related documents and files.

**Example:**
```markdown
### Add a Namespace to Pool

See also:
- [ClusterPool Definitions](../crossplane/cluster-pools.yaml)
- [Design Pattern: ClusterPool-Driven Policies](DESIGN-PATTERNS.md#pattern-10)
- [Troubleshoot Kyverno Issues](OPERATIONS-RUNBOOK.md#troubleshoot-kyverno)
```

### 4. Document Assumptions

**Rule:** If a procedure assumes a certain cluster state, document it.

**Example:**
```markdown
### Change Node Pool

**Prerequisites:**
- Node exists in cluster (ready status)
- All pods on node can tolerate platform-ha taint
- Storage replicas can migrate (if thalamus draining)

**Step 1:** ...
```

---

## Documentation Review Process

### Before Closing a Phase:

```bash
# 1. List all updated docs
git log --name-only --pretty=format: | grep "^docs/" | sort -u

# 2. Review each changed doc
for doc in $(git log --name-only --pretty=format: | grep "^docs/"); do
  echo "=== $doc ==="
  git show HEAD:$doc | head -50
done

# 3. Check links still valid
grep -r "\.md\|\.yaml" docs/crossplane/ | grep -E "^\[|https://" | head -20

# 4. Verify procedures are testable
grep -A 10 "^### " OPERATIONS-RUNBOOK.md | grep -E "kubectl|git" | wc -l
# Should be > 20 executable commands
```

---

## Timeline for P3

| Phase | Documentation | Effort | Timing |
|-------|---------------|--------|--------|
| **P0** | API rate limit analysis | 30 min | Done |
| **P1** | Kyverno integration guide | 4 hours | In progress |
| **P1 Completion** | Runbook updates | 2 hours | After P1 done |
| **P2** | Longhorn integration guide | 3 hours | If P2 implemented |
| **P2 Completion** | Runbook + patterns | 2 hours | If P2 done |

**Total Effort:** 8-12 hours of documentation (spread across 2-4 weeks)

---

## Success Criteria for P3

- [ ] OPERATIONS-RUNBOOK.md covers all procedures from P0-P2
- [ ] DESIGN-PATTERNS.md documents all architectural decisions
- [ ] AUDIT-INVENTORY.md reflects current cluster state
- [ ] All links and file references are valid
- [ ] Every procedure in runbook is tested and executable
- [ ] Documentation is reviewed before closing each phase

---

## Next Review Points

1. **After P0 Completes:** Update runbook with "Monitor API Health" section
2. **After P1 Completes:** Add "Manage Namespace Pools" and "Troubleshoot Kyverno" sections
3. **After P2 Completes** (if implemented): Add "Configure Node Storage" section
4. **Monthly:** Review all docs for accuracy, update examples if patterns change

---

**Owner:** Platform team (whoever implements each phase)  
**Effort:** Low (integrated with implementation, not separate phase)  
**Timing:** Ongoing throughout P0-P2
