# P1: ClusterPool-Kyverno Integration Guide

**Status:** 🟡 IN PROGRESS  
**Timeline:** 1-2 weeks  
**Complexity:** Medium  

---

## Overview

Integrate ClusterPool definitions with Kyverno policies to eliminate hardcoded namespace lists. This enables:
- ✅ Single source of truth (ClusterPool)
- ✅ Dynamic membership (no manual policy updates)
- ✅ Audit trail (all decisions in git)
- ✅ Simplified onboarding (label namespace → policy auto-applies)

---

## Phase 1a: Label Namespaces with Pool Membership

### Objective
Add `cryptophys.io/pool: {apps-ha|platform-ha|storage-only}` label to all cluster namespaces.

### Namespaces to Label

**apps-ha pool (11 namespaces):**
```
aide, cerebrum, apps-core, apps-dash, apps-user, bridge, automation,
apps-automation, apps-gateway, navigator, platform-ui
```

**platform-ha pool (27 namespaces):**
```
kube-system, flux-system, cert-manager, metallb-system, ingress-system,
spire-system, vault-system, kyverno-system, gatekeeper-system,
external-secrets, observability-system, registry-system, gitops-system,
security-system, facilitator, envoy-gateway-system, tetragon-system,
falco-system, trustedledger, dao-governance, cqls-compute, kueue-system,
crossplane-system, postgresql-system, tekton-system, tekton-pipelines,
tekton-chains, image-factory, monitoring-core, security-observability
```

**storage-only pool (2 namespaces):**
```
longhorn-system, minio-system, velero-system
```

### Implementation Options

#### Option A: Manual kubectl (Quick, 5 minutes)

```bash
# Apps HA pool
for ns in aide cerebrum apps-core apps-dash apps-user bridge automation \
          apps-automation apps-gateway navigator platform-ui; do
  kubectl label namespace $ns cryptophys.io/pool=apps-ha --overwrite
done

# Platform HA pool
for ns in kube-system flux-system cert-manager metallb-system ingress-system \
          spire-system vault-system kyverno-system gatekeeper-system \
          external-secrets observability-system registry-system gitops-system \
          security-system facilitator envoy-gateway-system tetragon-system \
          falco-system trustedledger dao-governance cqls-compute kueue-system \
          crossplane-system postgresql-system tekton-system tekton-pipelines \
          tekton-chains image-factory monitoring-core security-observability; do
  kubectl label namespace $ns cryptophys.io/pool=platform-ha --overwrite
done

# Storage only pool
for ns in longhorn-system minio-system velero-system; do
  kubectl label namespace $ns cryptophys.io/pool=storage-only --overwrite
done

# Verify
kubectl get namespaces -L cryptophys.io/pool | grep -v "<none>"
```

#### Option B: Git-based (Recommended, maintains audit trail)

1. Find all Namespace manifests in repos:
```bash
find /opt/cryptophys/repos -name "*.yaml" | xargs grep -l "^kind: Namespace$"
```

2. Edit each Namespace YAML to add label:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: aide
  labels:
    cryptophys.io/pool: apps-ha
```

3. Commit and push:
```bash
git add <updated-namespace-files>
git commit -m "chore: label namespaces with pool membership (ClusterPool)"
git push origin main
```

4. Flux will reconcile labels automatically within 10 minutes

**Recommended:** Option B (auditable, reversible)

### Verification

```bash
# Check labels applied
kubectl get ns -L cryptophys.io/pool

# Expected output:
# NAME                       STATUS   AGE   POOL
# aide                       Active   90d   apps-ha
# cerebrum                   Active   90d   apps-ha
# kube-system                Active   90d   platform-ha
# longhorn-system            Active   90d   storage-only
# ... (40+ more)
```

---

## Phase 1b: Create New Label-Based Kyverno Policies

### Objective
Create Kyverno policies that check namespace labels instead of hardcoded lists.

### Template Policies

Use the templates from `cluster-pool-namespace-labeling.yaml`:

1. **mutate-pool-tolerations-apps-ha**
   - Matches: `namespaceSelector: cryptophys.io/pool=apps-ha`
   - Injects: `cryptophys.io/pool: apps-ha` toleration

2. **mutate-pool-tolerations-platform-ha**
   - Matches: `namespaceSelector: cryptophys.io/pool=platform-ha`
   - Injects: `cryptophys.io/pool: platform-ha` toleration

3. **deny-storage-only-pods**
   - Matches: `namespaceSelector: cryptophys.io/pool=storage-only`
   - Denies: Workload pods (allows longhorn/minio/velero only)

### File Location

Create new file or update existing:
```
platform/infrastructure/policy/
├── cluster-pool-toleration-injection.yaml   [NEW]
└── cluster-pool-workload-restrictions.yaml  [NEW]
```

Or append to existing `nexus-placement-policy.yaml` and create new entry.

### Apply Policies

```bash
# Review policies before applying
kubectl apply -f platform/infrastructure/policy/cluster-pool-*.yaml --dry-run=client

# Apply
kubectl apply -f platform/infrastructure/policy/cluster-pool-*.yaml

# Verify
kubectl get clusterpolicies | grep "pool"
```

---

## Phase 1c: Test New Policies

### Test 1: Toleration Injection (apps-ha)

```bash
# Deploy test pod in apps-ha namespace
cat > /tmp/test-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-apps-ha
spec:
  containers:
  - name: test
    image: nginx
EOF

kubectl apply -f /tmp/test-pod.yaml -n aide

# Check if toleration was injected
kubectl get pod test-apps-ha -n aide -o yaml | grep -A 5 tolerations

# Expected: cryptophys.io/pool: apps-ha toleration should be present

kubectl delete pod test-apps-ha -n aide
```

### Test 2: Platform HA Toleration

```bash
cat > /tmp/test-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-platform-ha
spec:
  containers:
  - name: test
    image: nginx
EOF

kubectl apply -f /tmp/test-pod.yaml -n kube-system

# Check toleration
kubectl get pod test-platform-ha -n kube-system -o yaml | grep -A 5 tolerations

# Expected: cryptophys.io/pool: platform-ha toleration

kubectl delete pod test-platform-ha -n kube-system
```

### Test 3: Storage Pool Restriction

```bash
# Try to deploy workload pod in storage-only namespace
kubectl apply -f /tmp/test-pod.yaml -n longhorn-system

# Check events/audit (should show denial or audit message)
kubectl get event -n longhorn-system | grep -i "deny\|deny-storage"

# Expected: Audit showing policy denial (or actual denial if enforcing)

kubectl delete pod test-apps-ha -n longhorn-system 2>/dev/null
```

---

## Phase 1d: Deprecate Hardcoded Policies

### Identify Policies with Hardcoded Lists

Current files with hardcoded namespaces:
- `platform/infrastructure/policy/cp-restriction-policy.yaml` (34 hardcoded namespaces)
- `platform/infrastructure/policy/nexus-placement-policy.yaml` (11 hardcoded app namespaces)

### Deprecation Strategy

**Keep:**
- `cp-restriction-policy.yaml` → Controls control-plane access (unrelated to pools)

**Update:**
- `nexus-placement-policy.yaml` → Replace hardcoded list with pool label matching

**Example Update:**

```yaml
# OLD (lines 26-40):
namespaceSelector:
  matchExpressions:
  - key: kubernetes.io/metadata.name
    operator: In
    values:
    - aide
    - cerebrum
    - apps-core
    - apps-dash
    - ... (8 more hardcoded)

# NEW:
namespaceSelector:
  matchLabels:
    cryptophys.io/pool: apps-ha
```

### Implementation

```bash
# Edit the file
vim platform/infrastructure/policy/nexus-placement-policy.yaml

# Replace hardcoded namespaceSelector with label-based selector
# Then test:
kubectl apply -f platform/infrastructure/policy/nexus-placement-policy.yaml --dry-run=server

# Commit
git add platform/infrastructure/policy/nexus-placement-policy.yaml
git commit -m "refactor(p1): nexus-placement-policy uses pool labels instead of hardcoded lists"
git push origin main
```

---

## Phase 1e: Documentation Updates

### Files to Update

1. **OPERATIONS-RUNBOOK.md**
   - Add: "Adding a namespace to a pool" procedure
   - Example: Label namespace, policy auto-applies
   - Removed: Manual policy editing steps

2. **DESIGN-PATTERNS.md**
   - Add: ClusterPool-Kyverno integration pattern
   - Benefits: Single source of truth, dynamic membership
   - Trade-offs: Requires namespace labeling discipline

3. **AUDIT-INVENTORY.md**
   - Update: Kyverno policy section
   - Document: Pool-based policies + label requirements
   - Migration: Old hardcoded policies → new label-based

### Example Runbook Addition

```markdown
### Add a Namespace to a Pool

**Context:** You're creating a new namespace and need to assign it to a pool.

**Steps:**

1. **Create Namespace manifest:**
   ```yaml
   apiVersion: v1
   kind: Namespace
   metadata:
     name: my-new-app
     labels:
       cryptophys.io/pool: apps-ha  # ← Add pool label here
   ```

2. **Apply to cluster:**
   ```bash
   kubectl apply -f namespace.yaml
   ```

3. **Verify Kyverno policies apply:**
   - Deploy a pod in the namespace
   - Check: `kubectl get pod <name> -n my-new-app -o yaml | grep tolerations`
   - Expected: Pool-specific toleration injected automatically

**Benefits:**
- No manual policy editing
- Consistent with all other namespaces in pool
- Audit trail in git
- Policies auto-apply within seconds
```

---

## Success Criteria

### Phase 1a ✅
- [ ] All 40+ namespaces labeled with cryptophys.io/pool
- [ ] Labels match ClusterPool definitions
- [ ] kubectl get ns -L cryptophys.io/pool shows all pools represented

### Phase 1b ✅
- [ ] New label-based Kyverno policies created
- [ ] Policies deployed to cluster
- [ ] kubectl get clusterpolicies | grep pool shows ≥3 new policies

### Phase 1c ✅
- [ ] Test 1 (apps-ha toleration): PASS
- [ ] Test 2 (platform-ha toleration): PASS
- [ ] Test 3 (storage-only restriction): PASS or AUDIT

### Phase 1d ✅
- [ ] nexus-placement-policy.yaml updated (labels, no hardcoded list)
- [ ] Old policies still functional (backward compatible)
- [ ] All tests still pass with new policies

### Phase 1e ✅
- [ ] OPERATIONS-RUNBOOK.md updated
- [ ] DESIGN-PATTERNS.md documents integration
- [ ] AUDIT-INVENTORY.md reflects new policy structure

---

## Rollback Plan

If integration breaks Kyverno policies:

### Option 1: Quick Rollback (minutes)

```bash
# Delete new label-based policies
kubectl delete clusterpolicy mutate-pool-tolerations-apps-ha
kubectl delete clusterpolicy mutate-pool-tolerations-platform-ha
kubectl delete clusterpolicy deny-storage-only-pods

# Revert to git (old hardcoded policies restored)
git revert <commit-that-deleted-hardcoded-policy>

# Flux reconciles old policies
kubectl rollout restart deployment kyverno -n kyverno-system
```

### Option 2: Full Rollback (git revert)

```bash
# Revert entire P1 branch
git revert <first-P1-commit>..<last-P1-commit>

# Remove namespace labels
kubectl patch namespace aide -p '{"metadata":{"labels":{"cryptophys.io/pool":null}}}'
# (repeat for all namespaces)
```

---

## Implementation Timeline

```
Day 1-2:  Phase 1a (Namespace labeling)
Day 3:    Phase 1b (Create new policies)
Day 4:    Phase 1c (Testing)
Day 5-7:  Phase 1d (Deprecation) + Phase 1e (Documentation)
```

---

## Known Issues & Mitigation

### Issue 1: Namespace Label Misalignment

**Problem:** A namespace is labeled `cryptophys.io/pool: apps-ha` but ClusterPool has different namespaces.

**Prevention:**
- Double-check label values match ClusterPool.spec.namespaces
- Run comparison: `kubectl get clusterpool -o json | jq '.items[].spec.namespaces[]'`

**Mitigation:**
- Immediately update namespace label to correct pool
- Policy will re-apply with correct pool toleration

### Issue 2: Policy Doesn't Inject Toleration

**Problem:** Pod deployed in labeled namespace but toleration not injected.

**Diagnosis:**
```bash
kubectl get clusterpolicy mutate-pool-tolerations-apps-ha -o yaml | grep -A 20 rules
kubectl get pod <name> -n <ns> -o yaml | grep -A 5 tolerations
```

**Common Causes:**
- Policy has `background: false` (only applies to new pods)
- Pod existed before policy was created (recreate pod)
- Pod has `metadata.name` that doesn't match selector

**Fix:**
- Recreate pod: `kubectl delete pod <name> -n <ns>` (deployment will respawn)
- Check policy selector matches namespace label

### Issue 3: Hardcoded Policy Still Active

**Problem:** Both old hardcoded and new label-based policies are active (double injection).

**Mitigation:**
- Kyverno deduplicates tolerations (safe, not harmful)
- Once old policies deleted, issue resolves
- No immediate action needed, safe to deprecate gradually

---

## Next Steps

1. **Start Phase 1a:** Label namespaces (Option B: git-based)
2. **Create Phase 1b:** Deploy new policies to test cluster first
3. **Run Phase 1c:** Test procedures (validate integration works)
4. **Execute Phase 1d:** Update nexus-placement-policy.yaml
5. **Complete Phase 1e:** Update documentation

---

## References

- **ClusterPool definitions:** `platform/infrastructure/crossplane/cluster-pools.yaml`
- **Kyverno policy templates:** `platform/infrastructure/policy/cluster-pool-namespace-labeling.yaml`
- **Existing policies:** `platform/infrastructure/policy/`
- **Namespace manifests:** `platform/infrastructure/namespaces/` (or scattered in repos)

---

**Status:** Ready for implementation  
**Owner:** Platform team  
**Timeline:** 1-2 weeks  
**Risk:** Low (backward compatible, easily reversible)
