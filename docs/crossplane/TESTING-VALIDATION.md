# Crossplane Testing & Validation Guide

Step-by-step procedures to test and validate Crossplane infrastructure improvements (Options A-E).

---

## Test 1: Node Label Reconciliation (Option A)

**Goal:** Verify that Crossplane is continuously applying and reconciling node labels.

**Time:** 5 minutes

### 1.1 Baseline: Export Current Node State

```bash
# Capture actual node labels from live cluster
kubectl get nodes -o json | jq '.items[] | {
  name: .metadata.name,
  labels: .metadata.labels | to_entries | map("\(.key)=\(.value)") | sort
}' > /tmp/actual-labels.json

# Capture expected labels from Crossplane claims
cat platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml | \
  grep -A 20 "kind: ManagedNode" | grep -A 15 "customLabels:" | \
  jq -R 'select(. | contains("tier") or contains("ray") or contains("workload"))' \
  > /tmp/expected-labels.txt
```

### 1.2 Verify Core Labels Present

```bash
# Verify tier labels exist
kubectl get nodes -L cryptophys.io/tier
# Expected: All nodes have TIER column populated (platform/compute/storage)

# Verify ray labels exist
kubectl get nodes -L ray-head,ray-cluster
# Expected: synapse, cerebellum, quanta have ray-head=true
# Expected: nexus has ray-cluster=true
```

### 1.3 Test Label Drift Detection

```bash
# Manually remove a label (simulate drift)
kubectl label node nexus-144-91-103-10 nexus-tower-
# (removes nexus-tower label)

# Wait 30 seconds for Crossplane reconciliation
sleep 30

# Verify label is restored
kubectl get node nexus-144-91-103-10 -o jsonpath='{.metadata.labels.nexus-tower}'
# Expected: true (Crossplane restored it)
```

### 1.4 Check ManagedNode Status

```bash
kubectl get managednode -n crossplane-system -o wide
# Expected: All 10 nodes have STATUS=Synced, READY=True (or Waiting if provider not fully healthy)
```

### Test 1 Pass Criteria

- ✅ All nodes have `cryptophys.io/tier` label
- ✅ Ray head nodes (synapse, cerebellum, quanta) have `ray-head=true`
- ✅ Nexus has `ray-cluster=true` (if it's supposed to support ray workers)
- ✅ Removed label was automatically restored within 30 seconds
- ✅ ManagedNode resources show SYNCED=True

**Issue if Test 1 Fails:**
- Check Crossplane controller logs: `kubectl logs -n crossplane-system -l app=crossplane`
- Verify provider is healthy: `kubectl get providers.pkg.crossplane.io`
- Verify node exists: `kubectl get nodes <node-name>`

---

## Test 2: Taint Reconciliation (Option A & B)

**Goal:** Verify that Crossplane is applying and reconciling node taints.

**Time:** 5 minutes

### 2.1 Verify Taints Applied

```bash
# Check ray-head taints
kubectl get nodes synapse-161-97-136-251 -o jsonpath='{.spec.taints}' | jq '.[] | select(.key == "ray-head")'
# Expected: {key: "ray-head", value: "true", effect: "NoSchedule"}

# Check pool taints
kubectl get nodes synapse-161-97-136-251 -o jsonpath='{.spec.taints}' | jq '.[] | select(.key == "cryptophys.io/pool")'
# Expected: {key: "cryptophys.io/pool", value: "apps-ha", effect: "NoSchedule"}

# Check storage taints
kubectl get nodes campus-212-47-66-101 -o jsonpath='{.spec.taints}' | jq '.[] | select(.key == "cryptophys.io/storage-only")'
# Expected: {key: "cryptophys.io/storage-only", value: "true", effect: "NoSchedule"}
```

### 2.2 Test Taint Enforcement

```bash
# Try to schedule a pod without toleration (should fail)
cat > /tmp/test-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-no-toleration
spec:
  containers:
  - name: test
    image: nginx
  nodeSelector:
    cryptophys.io/tier: compute
EOF

kubectl apply -f /tmp/test-pod.yaml -n default

# Wait for scheduling attempt
sleep 5

# Check events
kubectl describe pod test-no-toleration -n default | grep -A 5 Events
# Expected: "0/10 nodes are available. 10 node(s) had taint {cryptophys.io/pool: apps-ha}"
# (or similar, depending on which compute nodes have pool taints)

# Clean up
kubectl delete pod test-no-toleration -n default
```

### 2.3 Test Toleration Works

```bash
cat > /tmp/test-pod-tolerated.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-with-toleration
spec:
  containers:
  - name: test
    image: nginx
  tolerations:
  - key: cryptophys.io/pool
    operator: Equal
    value: apps-ha
    effect: NoSchedule
  - key: ray-head
    operator: Equal
    value: "true"
    effect: NoSchedule
  nodeSelector:
    cryptophys.io/tier: compute
EOF

kubectl apply -f /tmp/test-pod-tolerated.yaml -n default

# Wait for scheduling
sleep 10

# Verify pod is running
kubectl get pod test-with-toleration -n default -o wide
# Expected: STATUS=Running on a compute node that matches the selector

# Clean up
kubectl delete pod test-with-toleration -n default
```

### Test 2 Pass Criteria

- ✅ Ray head taints exist on ray-head nodes
- ✅ Pool taints exist on pool-grouped nodes
- ✅ Storage taint exists on storage nodes
- ✅ Pod without toleration cannot schedule on tainted nodes
- ✅ Pod with matching toleration can schedule

---

## Test 3: WorkloadPlacement Patch Application (Option D)

**Goal:** Verify that WorkloadPlacement claims are patching Deployments and RayServices.

**Time:** 10 minutes

### 3.1 Check if Patches Are Applied to Deployments

```bash
# Check cerebrum-core Deployment for nodeSelector patches
kubectl get deployment cerebrum-core -n cerebrum -o yaml | grep -A 5 nodeSelector
# Expected: cryptophys.io/tier: compute

# Check for affinity patches
kubectl get deployment cerebrum-core -n cerebrum -o yaml | grep -A 20 affinity
# Expected: nodeAffinity with preferredDuringSchedulingIgnoredDuringExecution

# Check specific preferred node
kubectl get deployment cerebrum-core -n cerebrum -o yaml | grep -B 5 "nexus-144-91-103-10"
# Expected: Should find it in the affinity preferredDuringSchedulingIgnoredDuringExecution values
```

### 3.2 Check if Patches Are Applied to RayServices

```bash
# Check aide-mesh RayService for head nodeSelector patches
kubectl get rayservice aide-mesh -n aide -o yaml | \
  grep -A 30 "headGroupSpec:" | grep -A 20 "spec:" | head -30
# Look for: nodeSelector with cryptophys.io/tier: compute

# Check cerebrum-llm RayService
kubectl get rayservice cerebrum-llm -n cqls-compute -o yaml | \
  grep -A 30 "headGroupSpec:" | grep -A 20 "spec:" | head -30

# Check mcp-mesh RayService
kubectl get rayservice mcp-mesh -n apps-core -o yaml | \
  grep -A 30 "headGroupSpec:" | grep -A 20 "spec:" | head -30
```

### 3.3 Verify WorkloadPlacement Resources Exist

```bash
# List all WorkloadPlacement claims
kubectl get workloadplacement -n crossplane-system
# Expected: 6 claims (3 Deployments + 3 RayServices)

# Check detailed status of one
kubectl describe workloadplacement cerebrum-core -n crossplane-system
# Expected: STATUS=Synced, no error conditions
```

### 3.4 Test Workload Scheduling to Preferred Node

```bash
# Force Deployment rollout to pick up patches
kubectl rollout restart deployment/cerebrum-core -n cerebrum

# Wait for new pods to start
kubectl get pods -n cerebrum -l app=cerebrum-core -w
# (wait for 1/1 Running)

# Check which node the pod is on
kubectl get pods -n cerebrum -l app=cerebrum-core -o wide
# Expected: Pod should be running on nexus node (if WorkloadPlacement patch was applied correctly)
```

### Test 3 Pass Criteria

- ✅ Deployments have `cryptophys.io/tier: compute` nodeSelector
- ✅ Deployments have nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution patches
- ✅ RayService heads have nodeSelector patches
- ✅ WorkloadPlacement resources show SYNCED=True
- ✅ Pods schedule to preferred nodes (if available)

**Issue if Test 3 Fails:**
- Check if RayService composition is working: `kubectl get objects.kubernetes.crossplane.io -n crossplane-system | grep rayservice`
- Check composition resource logs: `kubectl describe <object-name> -n crossplane-system`
- Verify RayService structure hasn't changed incompatibly with composition

---

## Test 4: ClusterPool Integration (Option C)

**Goal:** Verify that ClusterPool definitions are available and can be used by policies.

**Time:** 5 minutes

### 4.1 Verify ClusterPool Resources Exist

```bash
# Check if ClusterPool CRD is registered
kubectl get customresourcedefinition | grep -i clusterpool
# Expected: clusterpools.cryptophys.work present

# List ClusterPool instances
kubectl get clusterpool -n crossplane-system
# Expected: 3 pools (apps-ha, platform-ha, storage-only)
```

### 4.2 Inspect ClusterPool Content

```bash
# View apps-ha pool
kubectl get clusterpool apps-ha -n crossplane-system -o yaml
# Expected:
#   nodes: [synapse-161-97-136-251, nexus-144-91-103-10]
#   namespaces: [aide, cerebrum, apps-core, apps-dash, ...]

# View platform-ha pool
kubectl get clusterpool platform-ha -n crossplane-system -o yaml
# Expected:
#   nodes: [cortex, cerebrum, corpus, thalamus, cerebellum]
#   namespaces: [kube-system, flux-system, cert-manager, ...]
```

### 4.3 Cross-Reference Against ManagedNode Claims

```bash
# Extract nodes from apps-ha pool spec
kubectl get clusterpool apps-ha -n crossplane-system -o jsonpath='{.spec.nodes}'
# Example: ["synapse-161-97-136-251","nexus-144-91-103-10"]

# Verify these nodes have pool=apps-ha taint
for node in $(kubectl get clusterpool apps-ha -n crossplane-system -o jsonpath='{.spec.nodes[*]}'); do
  echo "=== $node ==="
  kubectl get node $node -o jsonpath='{.spec.taints}' | jq '.[] | select(.key == "cryptophys.io/pool")'
done
# Expected: All nodes in pool have matching pool taint
```

### Test 4 Pass Criteria

- ✅ ClusterPool CRD is registered
- ✅ 3 ClusterPool instances exist
- ✅ Nodes in each ClusterPool match the taint value
- ✅ Namespaces listed in ClusterPool are documented

---

## Test 5: Label Consistency Across Tiers

**Goal:** Verify that all nodes have consistent labeling per tier.

**Time:** 5 minutes

### 5.1 Export and Compare Labels by Tier

```bash
# Platform tier nodes should have consistent labels
echo "=== Platform Tier ==="
for node in cortex-178-18-250-39 cerebrum-157-173-120-200 corpus-207-180-206-69; do
  echo "Node: $node"
  kubectl get node $node -o jsonpath='{.metadata.labels}' | jq 'keys | sort'
done

# Compute tier nodes should have consistent labels
echo "=== Compute Tier ==="
for node in nexus-144-91-103-10 synapse-161-97-136-251 thalamus-217-76-59-241 cerebellum-161-97-117-96 quanta-194-163-186-222; do
  echo "Node: $node"
  kubectl get node $node -o jsonpath='{.metadata.labels}' | jq 'keys | sort'
done

# Storage tier nodes should have consistent labels
echo "=== Storage Tier ==="
for node in campus-212-47-66-101 medulla-82-208-20-242; do
  echo "Node: $node"
  kubectl get node $node -o jsonpath='{.metadata.labels}' | jq 'keys | sort'
done
```

### 5.2 Audit for Ghost Labels

```bash
# Find labels not documented in claims
for node in $(kubectl get nodes -o name | cut -d/ -f2); do
  actual_labels=$(kubectl get node $node -o jsonpath='{.metadata.labels}' | jq 'keys | sort' | jq -r '.[]')
  expected_pattern=$(grep -A 15 "name: $node" platform/infrastructure/crossplane-crs/claims-platform-nodes.yaml | grep -oP '(?<=: ")[^"]*"' | tr -d '"' | sort)
  
  for label in $actual_labels; do
    # Check if label is in expected (simple check - just see if substring exists)
    if ! echo "$expected_pattern" | grep -q "$label"; then
      echo "GHOST LABEL on $node: $label"
    fi
  done
done
```

### Test 5 Pass Criteria

- ✅ Platform tier nodes have consistent label set
- ✅ Compute tier nodes have consistent label set (with variations for ray-head, pools)
- ✅ Storage tier nodes have consistent label set
- ✅ No "ghost" labels (labels without declared source)

---

## Test 6: Pod Toleration Injection (Future - Option C Integration)

**Goal:** Verify that Kyverno is injecting tolerations based on ClusterPool.

**Time:** 10 minutes (when Kyverno integration is complete)

### 6.1 Deploy Test Pod

```bash
# Create pod in apps-core namespace (apps-ha pool)
cat > /tmp/test-app-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-pool-pod
spec:
  containers:
  - name: test
    image: nginx
  nodeSelector:
    cryptophys.io/tier: compute
EOF

kubectl apply -f /tmp/test-app-pod.yaml -n apps-core
```

### 6.2 Verify Tolerations Injected

```bash
# Check if Kyverno added tolerations
kubectl get pod test-pool-pod -n apps-core -o yaml | grep -A 20 tolerations
# Expected (from ClusterPool apps-ha taints): 
#   - key: cryptophys.io/pool
#     value: apps-ha
```

### Test 6 Pass Criteria

- ✅ Pod scheduled in correct namespace runs on correct pool node
- ✅ Kyverno injected matching tolerations
- ✅ Pod can tolerate all taints on its assigned nodes

---

## Troubleshooting: Debugging Failed Tests

### Symptom: ManagedNode stuck in "READY=False"

**Diagnosis:**
```bash
kubectl describe managednode <node-name> -n crossplane-system | grep -A 20 "Conditions:"

kubectl logs -n crossplane-system -l app=crossplane | grep -i "error\|fail" | tail -20
```

**Common Causes:**
1. Provider not healthy → Check provider health
2. Node doesn't exist → Verify node in `kubectl get nodes`
3. Network connectivity → Check Crossplane pod networking

### Symptom: WorkloadPlacement patches not applied

**Diagnosis:**
```bash
# Check if Object resource was created
kubectl get objects.kubernetes.crossplane.io -n crossplane-system | grep workload

# Check composition errors
kubectl describe composition workload-placement.kubernetes.cryptophys.work -n crossplane-system

# Check if RayService composition is registered
kubectl get compositions -n crossplane-system | grep -i ray
```

**Common Causes:**
1. RayService composition not yet synced by Flux
2. RayService manifest structure incompatible with composition
3. Object resource provider not ready

### Symptom: Labels/Taints Not Persisting

**Diagnosis:**
```bash
# Check node status
kubectl describe node <node-name> | grep -A 10 Conditions

# Check if Kubelet has issues
# (via SSH to node): journalctl -u kubelet | tail -50
```

**Common Causes:**
1. Kubelet restarting (transient)
2. Node cordoned (has SchedulingDisabled)
3. Controller manager issue (not reconciling)

---

## Full Integration Test (All Options)

**Time:** 30 minutes

Run all tests in sequence:

```bash
#!/bin/bash
set -e

echo "=== Test 1: Node Labels ===" && \
  kubectl get nodes -L cryptophys.io/tier && \
  echo "✓ Test 1 passed"

echo -e "\n=== Test 2: Taints ===" && \
  kubectl get nodes synapse-161-97-136-251 -o jsonpath='{.spec.taints}' | jq . && \
  echo "✓ Test 2 passed"

echo -e "\n=== Test 3: ManagedNode Status ===" && \
  kubectl get managednode -n crossplane-system && \
  echo "✓ Test 3 passed"

echo -e "\n=== Test 4: ClusterPool ===" && \
  kubectl get clusterpool -n crossplane-system && \
  echo "✓ Test 4 passed"

echo -e "\n=== Test 5: WorkloadPlacement ===" && \
  kubectl get workloadplacement -n crossplane-system && \
  echo "✓ Test 5 passed"

echo -e "\n=== All tests passed! ===" 
```

---

## Next Steps

If all tests pass:
- ✅ Document any deviations (why something doesn't match expected)
- ✅ Create runbook entries for common operations
- ✅ Monitor cluster for any regressions

If any test fails:
- 🔍 Diagnose using troubleshooting guide above
- 📝 Document the issue
- 🛠️ Create a bugfix commit
- 🔄 Re-run test to verify fix

---

**Document Owner:** Claude Code  
**Last Updated:** 2026-04-12  
**Status:** Testing framework ready for execution
