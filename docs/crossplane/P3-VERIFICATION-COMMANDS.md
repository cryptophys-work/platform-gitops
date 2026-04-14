# P3 & P4 Verification Commands

Run these commands once the cluster is fully stable and all Flux reconciliations complete.

---

## Phase 1: Cluster Baseline (All Nodes Ready)

```bash
# Verify all 10 nodes Ready
kubectl get nodes -o wide | grep -E "Ready|NotReady"
# Expected: 10 Ready, 0 NotReady

# Verify Kyverno webhooks active
kubectl get endpoints -n kyverno-system kyverno-svc
# Expected: at least 1 endpoint address

# Verify API server responsive
kubectl cluster-info | head -3
# Expected: kubernetes-master at https://...
```

---

## Phase 2: P3-1 Verification (XRD + Composition Deployed)

```bash
# 2.1: XRD created
kubectl get xrd xclusterpools.cryptophys.work
# Expected: 
# NAME                         ESTABLISHED   OFFERED   READY   AGE
# xclusterpools.cryptophys.work   True         True      True    Xm

# 2.2: Composite resource (XClusterPool) created
kubectl get xclusterpools
# Expected: empty (composites are auto-created from claims)

# 2.3: ClusterPool claims exist in crossplane-system
kubectl get clusterpools -n crossplane-system
# Expected:
# NAME          STATUS
# apps-ha       Active
# platform-ha   Active
# storage-only  Active

# 2.4: Kyverno ClusterPolicies auto-generated from ClusterPool
kubectl get clusterpolicy | grep "mutate-pool-tolerations"
# Expected:
# mutate-pool-tolerations-apps-ha                   ...
# mutate-pool-tolerations-platform-ha               ...
# mutate-pool-tolerations-storage-only              ...

# 2.5: Verify Crossplane ownership annotation
kubectl get clusterpolicy mutate-pool-tolerations-apps-ha -o jsonpath='{.metadata.annotations.cryptophys\.io/managed-by}'
# Expected: crossplane

# 2.6: Verify policy structure (ensure Composition patches worked)
kubectl get clusterpolicy mutate-pool-tolerations-apps-ha -o jsonpath='{.spec.rules[0].match.any[0].resources.namespaceSelector.matchLabels}'
# Expected: map[cryptophys.io/pool:apps-ha]

# 2.7: Test policy: deploy pod in labeled namespace
kubectl label namespace teste-ns cryptophys.io/pool=apps-ha --overwrite
kubectl run test-pod -n teste-ns --image=nginx:latest 2>&1 | head -5
kubectl get pod test-pod -n teste-ns -o jsonpath='{.spec.tolerations}' | jq .
# Expected: array including cryptophys.io/pool=apps-ha:NoSchedule toleration

# 2.8: Cleanup test resources
kubectl delete pod test-pod -n teste-ns 2>/dev/null
kubectl label namespace teste-ns cryptophys.io/pool- 2>/dev/null
```

---

## Phase 3: P3-2 Verification (RayService Tolerations)

```bash
# 3.1: RayService toleration policies exist
kubectl get clusterpolicy | grep "rayservice-pool-toleration"
# Expected:
# mutate-rayservice-tolerations-apps-ha             ...
# mutate-rayservice-tolerations-platform-ha         ...

# 3.2: Verify policy has both head and worker rules
kubectl get clusterpolicy mutate-rayservice-tolerations-apps-ha -o jsonpath='{.spec.rules[].name}'
# Expected:
# inject-apps-ha-head-toleration
# inject-apps-ha-worker-tolerations

# 3.3: Verify RayService webhook (if cluster has test RayService)
# (Depends on KubeRay installation - skip if not installed)
kubectl get crd rayservices.ray.io 2>/dev/null && echo "KubeRay present" || echo "KubeRay not found - skipping"

# 3.4: Test RayService toleration injection (only if KubeRay present)
if kubectl get crd rayservices.ray.io 2>/dev/null; then
  kubectl apply -f - << 'EOF'
apiVersion: ray.io/v1
kind: RayService
metadata:
  name: test-ray
  namespace: aide  # labeled cryptophys.io/pool: apps-ha
spec:
  serveConfigV2: ""
  rayClusterConfig:
    headGroupSpec:
      template:
        spec:
          containers:
          - name: ray-head
            image: rayproject/ray:latest
    workerGroupSpecs: []
EOF
  
  # Wait a moment for admission
  sleep 2
  
  # Check head tolerations
  kubectl get rayservice test-ray -n aide -o jsonpath='{.spec.rayClusterConfig.headGroupSpec.template.spec.tolerations}' | jq .
  # Expected: includes cryptophys.io/pool=apps-ha:NoSchedule
  
  # Cleanup
  kubectl delete rayservice test-ray -n aide
fi
```

---

## Phase 4: P4-1 Verification (WorkloadPlacement Tolerations)

```bash
# 4.1: WorkloadPlacement claims exist
kubectl get workloadplacements -n crossplane-system
# Expected: 6 claims (cerebrum-core, cerebrum-llm, cerebrum-ollama, aide-mesh-ray-head, cerebrum-llm-ray-head, mcp-mesh-ray-head)

# 4.2: Verify cerebrum-core claim has tolerations
kubectl get workloadplacement cerebrum-core -n crossplane-system -o jsonpath='{.spec.placement.tolerations}'
# Expected: array with cryptophys.io/role=llm-inference:NoSchedule

# 4.3: Verify Composition applies tolerations to Deployment
# Check cerebrum-core Deployment in cerebrum namespace
kubectl get deployment cerebrum-core -n cerebrum -o jsonpath='{.spec.template.spec.tolerations}' 2>/dev/null | jq .
# Expected: includes both default tolerations AND cryptophys.io/role=llm-inference:NoSchedule

# 4.4: Verify RayService tolerations applied
# For aide-mesh-ray-head on quanta (bridge-system, dao-system, ray-head)
kubectl get rayservice aide-mesh -n aide -o jsonpath='{.spec.rayClusterConfig.headGroupSpec.template.spec.tolerations}' 2>/dev/null | jq .
# Expected: includes bridge-system, dao-system, ray-head tolerations

# Alternative: check mcp-mesh on apps-core
kubectl get rayservice mcp-mesh -n apps-core -o jsonpath='{.spec.rayClusterConfig.headGroupSpec.template.spec.tolerations}' 2>/dev/null | jq .
# Expected: same quanta tolerations
```

---

## Phase 5: Integration Tests (End-to-End)

```bash
# 5.1: Create test Deployment in apps-ha pool
kubectl label namespace test-apps-ha cryptophys.io/pool=apps-ha --overwrite 2>/dev/null
kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-apps-ha
  namespace: test-apps-ha
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
      - name: nginx
        image: nginx:latest
EOF

# 5.2: Verify Kyverno injected pool toleration
kubectl get deployment test-apps-ha -n test-apps-ha -o jsonpath='{.spec.template.spec.tolerations}' | jq .
# Expected: includes cryptophys.io/pool=apps-ha:NoSchedule (Kyverno-injected)

# 5.3: Verify pod can schedule on apps-ha nodes (synapse, nexus, quanta)
kubectl get pod -n test-apps-ha -o wide
# Expected: Pod running on synapse, nexus, or quanta node

# 5.4: Cleanup
kubectl delete deployment test-apps-ha -n test-apps-ha 2>/dev/null
kubectl delete namespace test-apps-ha 2>/dev/null

# 5.5: Create test Deployment with explicit WorkloadPlacement
# (Only if you want to test WorkloadPlacement directly)
# This would require a test Deployment in a real app namespace
# Skipped in this generic verification
```

---

## Phase 6: Monitoring & Health

```bash
# 6.1: Run monitoring dashboard
bash docs/crossplane/MONITORING-DASHBOARD.sh 10  # Update every 10 seconds

# 6.2: Check Cilium is healthy (fixed namespace bug)
bash docs/crossplane/MONITORING-DASHBOARD.sh | grep -A2 "CILIUM"

# 6.3: Verify Kyverno is not erroring
kubectl logs -n kyverno-system -l app.kubernetes.io/name=kyverno --tail=20 | grep -i error

# 6.4: Check for policy violations
kubectl get policyviolations --all-namespaces
# Expected: policy violations expected - this is normal with audit mode policies
```

---

## Known Issues & Workarounds

### Issue: "cryptophys.io/pool taint on nodes but no toleration injected"

**Cause:** Pod created before Kyverno policy was available, or webhook failed-open.

**Workaround:** Restart pod to trigger Kyverno injection on recreation:
```bash
kubectl rollout restart deployment <name> -n <namespace>
```

### Issue: "Crossplane webhook unreachable"

**Cause:** Crossplane pods on NotReady node (nexus recovery in progress).

**Status:** Fixed once nexus Ready. Flux will auto-reconcile.

**Workaround:** Manually force Flux reconciliation after nexus recovery:
```bash
flux reconcile kustomization -n flux-system 55-crossplane --with-source
```

### Issue: "WorkloadPlacement tolerations not applying to RayService workers"

**Cause:** Composition only patches `workerGroupSpecs[0]`. Multi-group services need manual fix or foreach loop.

**Workaround (for now):** Use Kyverno foreach policy for workers (already deployed as `rayservice-pool-toleration-injection.yaml`).

**Future:** Enhance composition with foreach loop for all worker groups.

---

## Checklist for P3 Completion

- [ ] All 10 nodes Ready
- [ ] XRD `xclusterpools.cryptophys.work` created
- [ ] 3 ClusterPolicies auto-generated with `cryptophys.io/managed-by: crossplane`
- [ ] Policy structure verified (namespaceSelector and toleration values correct)
- [ ] Test pod in labeled namespace gets toleration injection
- [ ] RayService policies exist and have both head + worker rules
- [ ] WorkloadPlacement claims all have `spec.placement.tolerations` array
- [ ] Cerebrum Deployments have correct llm-inference tolerations
- [ ] RayService workloads on quanta have correct tolerations
- [ ] Integration test: pod in apps-ha namespace runs on correct nodes
- [ ] MONITORING-DASHBOARD.sh shows Cilium healthy (kube-system, not cilium-system)

---

## Expected Timing

- **Phases 1-2:** <2 min (XRD + Composition deployment)
- **Phase 3:** <1 min (RayService policy verification)
- **Phase 4:** <2 min (WorkloadPlacement verification)
- **Phase 5:** <5 min (End-to-end integration)
- **Phase 6:** <5 min (Health check)

**Total:** ~15 minutes for complete P3 verification

---

**Run Date:** [YYYY-MM-DD HH:MM UTC]  
**Verifier:** [Name/Team]  
**Result:** ✅ PASSED / ⚠️ PARTIAL / ❌ FAILED

---

## If Verification Fails

1. Check **Known Issues** section above
2. Review logs in relevant namespaces:
   - `kubectl logs -n kyverno-system ...`
   - `kubectl logs -n crossplane-system ...`
   - `kubectl describe pod <pod> -n <namespace>`
3. Check Flux reconciliation status:
   - `kubectl get kustomization -n flux-system 55-crossplane`
   - `flux get all`
4. Escalate to platform team with logs and failing phase number
