# Cluster Recovery Runbook

**Date Created:** 2026-04-12  
**Target Cluster:** cryptophys-genesis (Talos v1.12.0, Kubernetes v1.35.0)  
**Current Issue:** Worker nodes NotReady, Cilium agents in crash loop  
**Severity:** CRITICAL — blocks all pod scheduling and cluster operations

---

## Situation Summary

### Symptoms
- ❌ All 7 worker nodes show `Ready: Unknown` status
- ❌ `node.cilium.io/agent-not-ready` taint on all worker nodes
- ❌ Cilium pods in CrashLoopBackOff (50+ restarts)
- ❌ No new pods can schedule
- ❌ Kyverno webhook endpoints empty (no replica pods running)
- ❌ API server timeouts concurrent with node failures

### Impact
- ⏳ P1c validation testing BLOCKED (requires pod scheduling)
- ⏳ P2 Longhorn reconciliation BLOCKED (controllers can't run)
- ⏳ P2 WorkloadPlacement patches BLOCKED (no pod scheduling)
- ❌ Production workloads FAILING (no capacity)

### Root Cause
Unknown — requires investigation. Possibilities:
1. Network connectivity issue (Cilium CNI misconfiguration)
2. kubelet crash or OOM
3. etcd health degradation
4. API server resource exhaustion
5. DNS/coredns failure
6. Kernel panic or driver issue

---

## Investigation Tree

### Phase 1: Quick Health Checks (5 minutes)

**1.1 Cluster API Health**
```bash
# Test API server connectivity
kubectl cluster-info

# Expected: Kubernetes master is running at https://api.cryptophys.work:6443

# If timeout or connection refused → API server issue
# → Jump to Section 3.1 (API Server Recovery)
```

**1.2 Node Status**
```bash
# Get node status summary
kubectl get nodes -o wide

# Expected: 10 nodes, at least 3 in Ready state (control-plane)
# Actual: 3 Ready (control-plane), 7 NotReady (workers)

# If all nodes NotReady → cluster bootstrap issue
# → Jump to Section 3.2 (Cluster Bootstrap)

# If workers NotReady but control-plane Ready → worker node issue
# → Continue to Phase 2
```

**1.3 Cilium Status**
```bash
# Check Cilium daemonset
kubectl get daemonset -n cilium-system

# Expected: cilium-l7-proxy, cilium, cilium-config-agent all with DESIRED == READY
# If not matching → pod scheduling blocked by kubelet

# Check specific cilium pod
kubectl get pod -n cilium-system -l k8s-app=cilium -o wide

# Expected: Running or Ready
# Actual: CrashLoopBackOff
```

**1.4 Worker Node Taints**
```bash
# Check taints on worker nodes
kubectl get node synapse-161-97-136-251 -o json | jq '.spec.taints'

# Expected: Only pool/storage/custom taints (apps-ha, platform-ha, storage-only)
# If includes: node.cilium.io/agent-not-ready → CNI issue
```

**1.5 etcd Health**
```bash
# From control-plane, check etcd
kubectl exec -n kube-system etcd-cortex-178-18-250-39 -- \
  etcdctl --endpoints=127.0.0.1:2379 endpoint health

# Expected: healthy, 1 healthy out of 3
# If unhealthy → etcd recovery needed (Section 3.3)
```

---

## Phase 2: Detailed Diagnosis (10-15 minutes)

### 2.1 Cilium Pod Logs

**Check agent pod on a failing worker:**
```bash
# Get Cilium pod on synapse (first failing node)
POD=$(kubectl get pod -n cilium-system -l k8s-app=cilium \
  --field-selector spec.nodeName=synapse-161-97-136-251 \
  -o jsonpath='{.items[0].metadata.name}')

# Check logs
kubectl logs -n cilium-system $POD --tail=100

# Look for:
# - "bind: permission denied" → SELinux or network namespace issue
# - "address already in use" → port conflict (8000, 9000, 9876)
# - "no such file or directory" → mount issue
# - "out of memory" → OOM kill
# - "signal: killed" → kubelet evicted pod
```

### 2.2 Kubelet Logs (via Talos)

**SSH to worker node:**
```bash
# Use talosctl (from jump host with kubeconfig)
talosctl logs controller/kubelet -n synapse-161-97-136-251

# Look for:
# - "failed to allocate for pod" → resource exhaustion
# - "container runtime" errors → containerd issues
# - "network setup failed" → CNI plugin failure
# - "permission denied" → SELinux/AppArmor
```

**Alternative (if talosctl unavailable):**
```bash
# Via control-plane SSH
ssh -i ~/.ssh/talos synapse@161.97.136.251

# Inspect kubelet process
ps aux | grep kubelet

# Check kubelet logs
journalctl -u kubelet -n 100
```

### 2.3 Network Connectivity

**From control-plane to worker:**
```bash
# Test network access to worker kubelet
curl -k https://synapse-161-97-136-251:10250/stats

# Expected: Connection successful, returns kubelet stats
# If timeout → network issue
# If "connection refused" → kubelet not listening

# Test DNS
kubectl run -it debug --image=busybox:latest --restart=Never -- \
  nslookup kubernetes.default.svc.cluster.local

# Expected: resolves to ClusterIP
# If fails → coredns issue
```

### 2.4 Node Resource Pressure

**Check node conditions:**
```bash
kubectl get node synapse-161-97-136-251 -o json | \
  jq '.status.conditions[] | {type, status, reason, message}'

# Look for:
# - MemoryPressure: True → node low on memory
# - DiskPressure: True → disk space low
# - PIDPressure: True → too many processes
# - Ready: Unknown → communication lost
```

**Check allocatable resources:**
```bash
kubectl describe node synapse-161-97-136-251 | grep -A 5 Allocatable

# Expected: memory and CPU available
# If low/unavailable → kubelet configuration issue
```

### 2.5 Container Runtime Health

**Check containerd status:**
```bash
# Via talosctl
talosctl exec -n synapse-161-97-136-251 -- \
  ctr version

# Via direct SSH
ssh -i ~/.ssh/talos synapse@161.97.136.251
systemctl status containerd
journalctl -u containerd -n 50
```

---

## Phase 3: Recovery Procedures

### 3.1 API Server Recovery

**If API server not responding:**

**Step 1: Verify API is reachable**
```bash
# Check on control-plane
kubectl logs -n kube-system -l component=kube-apiserver --tail=50

# Look for panic, OOM, or segfault
```

**Step 2: Check API server resources**
```bash
# Get API pod details
kubectl get pod -n kube-system -l component=kube-apiserver -o wide

# Check resource usage
kubectl top pod -n kube-system -l component=kube-apiserver
```

**Step 3: If OOM or high CPU**
```bash
# API server may need restart (graceful)
kubectl delete pod -n kube-system \
  -l component=kube-apiserver \
  --grace-period=30

# Wait for restart
kubectl wait --for=condition=Ready pod \
  -n kube-system -l component=kube-apiserver \
  --timeout=300s
```

**Step 4: Monitor recovery**
```bash
kubectl get nodes -w
kubectl get pod -n kube-system -w -l component=kube-apiserver
```

### 3.2 Cluster Bootstrap Recovery

**If all nodes including control-plane are NotReady:**

**This requires Talos-level recovery:**

**Step 1: Access Talos control plane**
```bash
# From jump host with talosctl access
talosctl kubeconfig -n cortex-178-18-250-39

# Verify you can reach Talos API
talosctl nodes -n cortex-178-18-250-39
```

**Step 2: Check Talos system health**
```bash
# Check all nodes booted correctly
talosctl dmesg -n cortex-178-18-250-39 | tail -20
talosctl dmesg -n synapse-161-97-136-251 | tail -20

# Look for kernel panics, OOM kills, or boot errors
```

**Step 3: Reboot problematic nodes (if needed)**
```bash
# Graceful reboot of single node
talosctl reboot -n synapse-161-97-136-251

# Wait for node to come back
kubectl wait --for=condition=Ready node/synapse-161-97-136-251 --timeout=600s

# Monitor system again
kubectl get nodes -w
```

**Step 4: If reboot doesn't help, check Talos machine config**
```bash
# Get current config
talosctl edit machineconfig -n synapse-161-97-136-251

# Key items to verify:
# - kubelet.extraArgs.max-pods: should be 300 for nexus (220+ for others)
# - kubelet.extraArgs.system-reserved matches control-plane
# - Network interface config correct
# - Kernel args (IOMMU, hugepages) present
```

### 3.3 etcd Recovery

**If etcd cluster is degraded:**

**Step 1: Check etcd status**
```bash
# From control-plane
kubectl exec -n kube-system -it etcd-cortex-178-18-250-39 -- \
  etcdctl --endpoints=127.0.0.1:2379 member list

# Check for unhealthy members (high send/recv packets, slow)
```

**Step 2: If one member is stuck**
```bash
# Remove problematic member (careful!)
kubectl exec -n kube-system -it etcd-cortex-178-18-250-39 -- \
  etcdctl --endpoints=127.0.0.1:2379 member remove <member-id>

# Wait for it to re-initialize
kubectl wait --for=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'=True \
  pod/etcd-synapse-161-97-136-251 -n kube-system --timeout=300s
```

**Step 3: Monitor recovery**
```bash
# Watch member list
kubectl exec -n kube-system etcd-cortex-178-18-250-39 -- \
  etcdctl --endpoints=127.0.0.1:2379 member list --write-out=json | jq '.members[] | {id, name, status: "healthy"}'
```

### 3.4 Cilium Recovery

**If Cilium agents are CrashLoopBackOff:**

**Step 1: Check for conflicting CNI**
```bash
# Ensure no other CNI plugins
kubectl get ds -n kube-system | grep -E 'weave|flannel|calico|kube-proxy'

# If present and not needed, remove them
kubectl delete ds -n kube-system <conflicting-cni>
```

**Step 2: Reset Cilium config**
```bash
# Delete and recreate Cilium config
kubectl delete configmap -n kube-system cilium-config

# Flux should recreate it
kubectl get helmrelease -n kube-system cilium

# If not reconciling, trigger manual:
kubectl patch helmrelease -n kube-system cilium \
  -p '{"spec":{"suspend":false}}' --type merge
```

**Step 3: Delete Cilium pods to force restart**
```bash
# Kill all Cilium agents
kubectl delete pod -n cilium-system -l k8s-app=cilium

# Wait for new pods to start
kubectl wait --for=condition=Ready pod \
  -n cilium-system -l k8s-app=cilium \
  --timeout=300s

# Monitor logs
kubectl logs -n cilium-system -l k8s-app=cilium --tail=50 -f
```

**Step 4: If still failing, check node network**
```bash
# Verify vxlan/geneve interface exists
talosctl exec -n synapse-161-97-136-251 -- ip link show | grep -E 'cilium|vxlan|geneve'

# Expected: cilium_vxlan or similar interface
# If missing → Cilium pod can't set up network

# Check eBPF mounts
talosctl exec -n synapse-161-97-136-251 -- mount | grep bpf

# Expected: /sys/fs/bpf type bpf
# If missing → needs kernel feature (BPF)
```

### 3.5 Worker Node Recovery

**Generic worker node recovery (if single node failing):**

**Step 1: Drain and reboot**
```bash
# Safely drain workloads
kubectl drain synapse-161-97-136-251 --ignore-daemonsets --delete-emptydir-data

# Reboot
talosctl reboot -n synapse-161-97-136-251

# Wait for node to return
kubectl wait --for=condition=Ready node/synapse-161-97-136-251 --timeout=600s

# Uncordon
kubectl uncordon synapse-161-97-136-251
```

**Step 2: Monitor recovery**
```bash
# Watch node come back
kubectl get node synapse-161-97-136-251 -w

# Check pod scheduling
kubectl get pod -n default --field-selector spec.nodeName=synapse-161-97-136-251

# Verify taints removed (should only have pool/ray taints, not agent-not-ready)
kubectl get node synapse-161-97-136-251 -o json | jq '.spec.taints'
```

**Step 3: If node still NotReady after reboot**
```bash
# Re-provision node with Talos
talosctl apply-config -n synapse-161-97-136-251 -f talos/synapse/talos__synapse_worker.yaml

# This will reboot and reconfigure
# Monitor for ~5 minutes
kubectl get node synapse-161-97-136-251 -w
```

---

## Phase 4: Validation

### 4.1 Cluster Health Checks

**After recovery, verify health:**

```bash
# All nodes Ready
kubectl get nodes
# Expected: 3 Ready (control-plane), 7 Ready (workers)

# No NotReady or unknown statuses
kubectl get nodes -o json | jq '.items[] | select(.status.conditions[] | select(.type=="Ready" and .status!="True"))'
# Expected: No output

# All system pods Running
kubectl get pod -n kube-system --field-selector=status.phase!=Running
# Expected: No output

# Cilium healthy
kubectl get daemonset -n cilium-system -o wide
# Expected: DESIRED == READY == UP-TO-DATE for all daemonsets

# API server responsive
kubectl cluster-info
# Expected: Kubernetes master is running at https://api.cryptophys.work:6443

# etcd healthy
kubectl exec -n kube-system etcd-cortex-178-18-250-39 -- \
  etcdctl --endpoints=127.0.0.1:2379 endpoint health
# Expected: healthy, 1 healthy out of 3
```

### 4.2 Webhook Health Checks

**After nodes are Ready, verify webhooks:**

```bash
# Kyverno webhook endpoints
kubectl get endpoints -n kyverno-system kyverno-svc
# Expected: At least 1 IP address listed

# Cert-manager webhook
kubectl get pod -n cert-manager -l app.kubernetes.io/name=webhook
# Expected: Running

# Test webhook accessibility
kubectl get pod -n default -o yaml | head -20
# Should show policy mutation applied (look for toleration injections)
```

### 4.3 P1c Testing Readiness

**Before running P1-VALIDATION-CHECKLIST.md:**

```bash
# Pre-validation requirements from checklist
✅ All worker nodes Ready status
  kubectl get nodes | grep -E '^(synapse|thalamus|cerebellum|quanta|campus|medulla|nexus)'

✅ Kyverno webhook endpoints populated
  kubectl get endpoints -n kyverno-system kyverno-svc

✅ API server responding without timeouts
  kubectl cluster-info && kubectl api-resources

✅ Cluster stable for ≥5 minutes
  kubectl get nodes -w & sleep 300; pkill -f "get nodes"
  # Should show no transitions during 5-minute window
```

---

## Recovery Timeline Expectations

| Recovery Type | Expected Duration | Monitoring Command |
|---------------|-------------------|-------------------|
| API server restart | 2-3 min | `kubectl get apiservice \| grep -i local` |
| Cilium agent restart | 5-10 min | `kubectl get ds -n cilium-system -w` |
| Single node reboot | 5-10 min | `kubectl get node <name> -w` |
| Full cluster reboot | 15-30 min | `kubectl get nodes -w` |
| etcd member recovery | 10-20 min | `kubectl exec -it etcd-* -- etcdctl member list` |

---

## Escalation Path

### If recovery procedures don't restore cluster health within 30 minutes:

1. **Escalate to Infrastructure/Talos Team** with:
   - Output of `kubectl get nodes -o json`
   - Cilium pod logs (last 100 lines)
   - etcd member list output
   - Talos dmesg from failing nodes
   - Exact time cluster went NotReady

2. **Parallel: Check for known issues**
   - Talos v1.12.0 release notes (check for critical bugs)
   - Cilium v1.x compatibility with Kubernetes v1.35.0
   - Recent infrastructure changes (network, firmware, OS updates)

3. **If long-term failure:**
   - Consider node re-imaging via Talos machine config
   - Check if cluster needs etcd backup recovery
   - Prepare to fail over to standby cluster (if available)

---

## Prevention (Post-Recovery)

### Monitoring & Alerting
```yaml
# Add to monitoring stack:
- Alert: Node NotReady for >2 minutes
- Alert: Cilium pod CrashLoopBackOff
- Alert: etcd member unhealthy
- Alert: API server response time >100ms
```

### Regular Health Checks
```bash
# Daily check
kubectl get nodes -o wide
kubectl get daemonset -n cilium-system

# Weekly deep-dive
talosctl nodes  # Verify all nodes in cluster
etcdctl endpoint health
```

### Capacity Planning
- Monitor worker node CPU/memory before reaching limits
- Pre-stage replacement nodes if any node approaching 90% utilization
- Test recovery procedures monthly (chaos engineering)

---

## Related Documentation

- `docs/crossplane/MASTER-STATUS-2026-04-12.md` — Current cluster status
- `docs/crossplane/OPERATIONS-RUNBOOK.md` — API health monitoring procedures
- Talos Docs: https://www.talos.dev/latest/learn-more/troubleshooting/
- Cilium Docs: https://docs.cilium.io/en/stable/troubleshooting/

---

**Owner:** Platform Team  
**Last Updated:** 2026-04-12  
**Next Review:** Post-recovery or 2026-04-19
