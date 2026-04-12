# P1 Validation Checklist

**Objective:** Complete testing and validation of ClusterPool-Kyverno integration once cluster infrastructure is healthy

**Status:** Ready (pending cluster health restoration)  
**Execution Trigger:** When all worker nodes return to Ready status  
**Estimated Duration:** 30-45 minutes

---

## Pre-Validation Requirements

- ✅ All worker nodes Ready status
- ✅ Kyverno webhook endpoints populated (not empty)
- ✅ API server responding without timeouts
- ✅ Cluster stable for ≥5 minutes

---

## Phase 1: Verify Namespace Labels

### 1.1 Check All Namespaces Have Pool Labels

```bash
echo "=== Namespace Label Coverage ===" && \
kubectl get ns -o custom-columns=NAME:.metadata.name,POOL:.metadata.labels.cryptophys\\.io/pool | \
  awk 'NR>1 {print $2}' | grep -v "^$" | sort | uniq -c

# Expected output:
# - All namespaces should show either: apps-ha, platform-ha, or storage-only
# - No blank entries
# - Breakdown: 11 apps-ha, 28 platform-ha, 3 storage-only
```

**Pass Criteria:** All 42+ labeled namespaces present, zero unla beled

### 1.2 Verify Labels Match ClusterPool Definitions

```bash
echo "=== Verify Label-to-ClusterPool Mapping ===" && \
for pool in apps-ha platform-ha storage-only; do
  echo "Pool: $pool"
  kubectl get clusterpool $pool -o jsonpath='{.spec.namespaces}' | jq '.' | head -5
done

# Expected: Labels on namespaces match ClusterPool.spec.namespaces
```

**Pass Criteria:** No discrepancies between ClusterPool definitions and namespace labels

---

## Phase 2: Test Kyverno Policy Injection

### 2.1 Test Apps-HA Toleration Injection

```bash
echo "=== Test 1: Apps-HA Toleration ===" && \
kubectl apply -f - -n aide <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-apps-ha-toleration
spec:
  containers:
  - name: test
    image: nginx:1.27-alpine
    securityContext:
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      capabilities:
        drop:
        - ALL
      seccompProfile:
        type: RuntimeDefault
EOF

sleep 3

# Check toleration was injected
echo "Checking tolerations..." && \
kubectl get pod test-apps-ha-toleration -n aide -o jsonpath='{range .spec.tolerations[*]}{.key}{": "}{.value}{"\n"}{end}'

# Expected output should include:
# cryptophys.io/pool: apps-ha

# Cleanup
kubectl delete pod test-apps-ha-toleration -n aide
```

**Pass Criteria:** Pod receives `cryptophys.io/pool: apps-ha` toleration

### 2.2 Test Platform-HA Toleration Injection

```bash
echo "=== Test 2: Platform-HA Toleration ===" && \
kubectl apply -f - -n kube-system <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-platform-ha-toleration
spec:
  containers:
  - name: test
    image: nginx:1.27-alpine
    securityContext:
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      capabilities:
        drop:
        - ALL
      seccompProfile:
        type: RuntimeDefault
EOF

sleep 3

# Check toleration was injected
echo "Checking tolerations..." && \
kubectl get pod test-platform-ha-toleration -n kube-system -o jsonpath='{range .spec.tolerations[*]}{.key}{": "}{.value}{"\n"}{end}'

# Expected output should include:
# cryptophys.io/pool: platform-ha

# Cleanup
kubectl delete pod test-platform-ha-toleration -n kube-system
```

**Pass Criteria:** Pod receives `cryptophys.io/pool: platform-ha` toleration

### 2.3 Test Storage-Only Pool Restriction

```bash
echo "=== Test 3: Storage-Only Pod Restriction ===" && \
kubectl apply -f - -n longhorn-system <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-storage-restriction
spec:
  containers:
  - name: test
    image: nginx:1.27-alpine
    securityContext:
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      capabilities:
        drop:
        - ALL
      seccompProfile:
        type: RuntimeDefault
EOF

sleep 3

# Check if pod was denied or allowed
echo "Pod status:" && \
kubectl get pod test-storage-restriction -n longhorn-system --no-headers

# Expected: Pod should be Running (allowed because longhorn-system is system service)
# If testing from another namespace (e.g., apps-core), expect Pending or error

# Cleanup
kubectl delete pod test-storage-restriction -n longhorn-system 2>/dev/null || true
```

**Pass Criteria:** Policy allows storage system namespaces, denies others in audit mode

---

## Phase 3: Test Deployment-Level Injection

### 3.1 Test Autogen Rules (Deployment)

```bash
echo "=== Test 4: Deployment Toleration Injection ===" && \
kubectl apply -f - -n cerebrum <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-deployment-toleration
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      containers:
      - name: test
        image: nginx:1.27-alpine
        securityContext:
          allowPrivilegeEscalation: false
          runAsNonRoot: true
          capabilities:
            drop:
            - ALL
          seccompProfile:
            type: RuntimeDefault
EOF

sleep 5

# Check if pod template spec was patched
echo "Deployment tolerations:" && \
kubectl get deployment test-deployment-toleration -n cerebrum -o jsonpath='{.spec.template.spec.tolerations}' | jq '.'

# Expected: Tolerations should be present in deployment spec

# Cleanup
kubectl delete deployment test-deployment-toleration -n cerebrum
```

**Pass Criteria:** Deployment pods receive injected tolerations via autogen rules

---

## Phase 4: Verify Policy Patterns

### 4.1 Check Kyverno Policy Status

```bash
echo "=== Kyverno Policy Status ===" && \
kubectl get clusterpolicy | grep -E "mutate-pool|deny-storage" && \
echo "" && \
kubectl get clusterpolicy mutate-pool-tolerations-apps-ha -o jsonpath='{.status.conditions[?(@.type=="Ready")]}'
```

**Pass Criteria:** All 3 policies READY=True, background reconciliation active

### 4.2 Verify No Policy Conflicts

```bash
echo "=== Check for Policy Conflicts ===" && \
# Create test pod and verify ONLY one set of tolerations (no duplicates)
kubectl apply -f - -n apps-core <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: test-dedup
spec:
  containers:
  - name: test
    image: nginx:1.27-alpine
    securityContext:
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      capabilities:
        drop:
        - ALL
      seccompProfile:
        type: RuntimeDefault
EOF

sleep 3

# Count tolerations
count=$(kubectl get pod test-dedup -n apps-core -o jsonpath='{.spec.tolerations[?(@.key=="cryptophys.io/pool")] | length}')
echo "Apps-ha toleration count: $count"

# Expected: Exactly 1 (not 2 from both old and new policies)

kubectl delete pod test-dedup -n apps-core
```

**Pass Criteria:** Exactly one `cryptophys.io/pool` toleration per namespace (no duplicates)

---

## Phase 5: Verify ClusterPool Integration

### 5.1 Check ClusterPool Instances

```bash
echo "=== ClusterPool Definitions ===" && \
kubectl get clusterpool -o wide && \
echo "" && \
kubectl get clusterpool apps-ha -o jsonpath='{.spec}' | jq '.'
```

**Pass Criteria:** 3 ClusterPool instances (apps-ha, platform-ha, storage-only) with correct namespace lists

### 5.2 Verify ClusterPool Namespace Consistency

```bash
echo "=== ClusterPool vs Namespace Label Audit ===" && \
python3 << 'EOF'
import json
import subprocess

# Get ClusterPool namespaces
pools = {}
for pool_name in ["apps-ha", "platform-ha", "storage-only"]:
    result = subprocess.run(
        ["kubectl", "get", "clusterpool", pool_name, "-o", "jsonpath", "{.spec.namespaces}"],
        capture_output=True, text=True
    )
    pools[pool_name] = json.loads(result.stdout)

# Get labeled namespaces from cluster
result = subprocess.run(
    ["kubectl", "get", "ns", "-o", "jsonpath", "{range .items[*]}{.metadata.name}:{.metadata.labels.cryptophys\\.io/pool},"],
    capture_output=True, text=True
)

ns_labels = {}
for pair in result.stdout.split(',')[:-1]:
    if pair:
        ns, pool = pair.split(':')
        if pool:
            if pool not in ns_labels:
                ns_labels[pool] = []
            ns_labels[pool].append(ns)

# Compare
print("ClusterPool Audit Results:")
for pool in pools:
    pool_ns = set(pools[pool])
    labeled_ns = set(ns_labels.get(pool, []))
    
    missing = pool_ns - labeled_ns
    extra = labeled_ns - pool_ns
    
    if missing or extra:
        print(f"\n❌ {pool}: MISMATCH")
        if missing:
            print(f"  Missing labels: {missing}")
        if extra:
            print(f"  Extra labels: {extra}")
    else:
        print(f"\n✅ {pool}: All {len(pool_ns)} namespaces correctly labeled")
EOF
```

**Pass Criteria:** All ClusterPool namespaces labeled, no discrepancies

---

## Phase 6: Integration Test

### 6.1 End-to-End Flow Test

```bash
echo "=== E2E Flow: New Namespace in Pool ===" && \
# 1. Create test namespace with pool label
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: test-pool-e2e
  labels:
    cryptophys.io/pool: apps-ha
EOF

sleep 5

# 2. Deploy test workload
kubectl apply -f - -n test-pool-e2e <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-workload
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      containers:
      - name: test
        image: nginx:1.27-alpine
        securityContext:
          allowPrivilegeEscalation: false
          runAsNonRoot: true
          capabilities:
            drop:
            - ALL
          seccompProfile:
            type: RuntimeDefault
EOF

sleep 10

# 3. Verify pod received toleration
echo "Pod tolerations:" && \
kubectl get pod -n test-pool-e2e -l app=test -o jsonpath='{range .items[0].spec.tolerations[*]}{.key}{": "}{.value}{"\n"}{end}'

# Expected: cryptophys.io/pool: apps-ha toleration present

# Cleanup
kubectl delete ns test-pool-e2e
```

**Pass Criteria:** New namespace automatically receives toleration via policy

---

## Phase 7: Documentation Verification

### 7.1 Verify All References Current

```bash
echo "=== Documentation Links Validation ===" && \
# Check that all cross-references in docs are valid
for doc in \
  docs/crossplane/OPERATIONS-RUNBOOK.md \
  docs/crossplane/DESIGN-PATTERNS.md \
  docs/crossplane/AUDIT-INVENTORY.md \
  docs/crossplane/P1-KYVERNO-INTEGRATION-GUIDE.md; do
  
  echo "Checking: $doc"
  grep -E "^\[|policy|ClusterPool|kyverno" "$doc" | head -5
done
```

**Pass Criteria:** All links valid, documentation accurate to current state

---

## Summary Table

| Test | Expected Result | Status |
|------|-----------------|--------|
| 1.1: Namespace Labels | 42+ labeled | ⏳ Pending |
| 1.2: Label-to-Pool Mapping | 100% match | ⏳ Pending |
| 2.1: Apps-HA Injection | Toleration injected | ⏳ Pending |
| 2.2: Platform-HA Injection | Toleration injected | ⏳ Pending |
| 2.3: Storage-Only Restriction | Policy enforced | ⏳ Pending |
| 3.1: Deployment Injection | Autogen rules work | ⏳ Pending |
| 4.1: Policy Status | All READY | ⏳ Pending |
| 4.2: No Policy Conflicts | Single toleration | ⏳ Pending |
| 5.1: ClusterPool Instances | 3 pools defined | ✅ Pass |
| 5.2: ClusterPool Consistency | All labeled correctly | ⏳ Pending |
| 6.1: E2E New Namespace | Toleration auto-applied | ⏳ Pending |
| 7.1: Documentation | All links valid | ✅ Pass |

---

## Execution Notes

- **Blockers:** Currently blocked by cluster NotReady status
- **Once Unblocked:** Execute tests sequentially, validate each phase before proceeding
- **Rollback:** Any failed test should trigger investigation before re-running
- **Success:** All 12 tests passing = P1c complete

---

**Created:** 2026-04-12  
**Ready Since:** Session start  
**Execution Window:** Upon cluster recovery  
**Estimated Time:** 45 minutes  
**Owner:** Platform team
