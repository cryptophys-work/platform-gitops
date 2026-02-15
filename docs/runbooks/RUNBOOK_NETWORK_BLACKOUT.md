# RUNBOOK: Network Blackout Recovery & Prevention

**Last Updated:** 2026-02-09
**Severity:** Critical
**Context:** Cilium CNI Deadlock / Policy Denial leading to Cluster Blackout.

## 1. Prevention Architecture
The cluster relies on `00-base-system-protection` (CiliumClusterwideNetworkPolicy) to guarantee:
- All Pods -> Kube API Server
- All Pods -> CoreDNS
- Host -> Pods (Health Checks)

**DO NOT DELETE** this policy unless upgrading Cilium.

## 2. Diagnosis (Is it a Blackout?)
If `kubectl get pods` works but pods are crashing with DNS/Network timeouts:
1. Run a debug pod on a specific node:
   ```bash
   kubectl run debug-net --rm -i --tty --image=curlimages/curl --restart=Never 
     --overrides='{"spec": {"nodeName": "cortex-178-18-250-39"}}' 
     -- curl -kv https://10.96.0.1:443
   ```
2. If this times out, the **CNI Datapath is broken**.

## 3. Recovery Procedure (The "Break Glass" Protocol)

### Phase 1: Apply Emergency Policy
If policy updates are still working, apply this permissive policy to regain control.
```yaml
apiVersion: "cilium.io/v2"
kind: CiliumClusterwideNetworkPolicy
metadata:
  name: "network-emergency-rescue"
spec:
  description: "EMERGENCY ONLY"
  endpointSelector: {}
  ingress: [{fromEntities: ["all"]}]
  egress: [{toEntities: ["all"]}]
```

### Phase 2: Hard Reset (If Phase 1 fails)
If agents are deadlocked, force a restart to reload BPF maps.
```bash
kubectl delete pod -n kube-system -l k8s-app=cilium --force --grace-period=0
```

### Phase 3: Stabilization
1. Restart `coredns` and `longhorn-manager`.
2. Verify connectivity.
3. **DELETE** the emergency policy from Phase 1.

## 4. Post-Incident Verification
- Check `cilium status --verbose` for "Policy denied" drops.
- Verify `longhorn` volumes are attached.
