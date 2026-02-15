# EXECUTION PLAN - RECOVERY OF TRUE FULL MESH WIREGUARD

## 1. INTENT
Restore the cluster to its production ground truth by re-establishing the host-level Wireguard mesh (10.8.0.x) and Cilium encryption. Current fragmentation (10.0.x.x node IPs) is a regression caused by unauthorized mutation.

## 2. APPROVAL (PENDING)
- AI Internal Deployment Engineer (Initiator)
- User (Final Approver)

## 3. EXECUTION STEPS
1.  **Node IP Verification:** Force nodes to prioritize `wg0` (10.8.0.x) for Cilium peer identification.
2.  **Cilium Config Alignment:** Set `kube-proxy-replacement: strict`, `enable-wireguard: true`, and `devices: wg0`.
3.  **CoreDNS/API Recovery:** Ensure internal service discovery works across the mesh.
4.  **MinIO Restoration:** Re-enable volume mounting once node-to-node connectivity is stable.

## 4. EVIDENCE
- `cilium-health status` = 5/5 reachable.
- Node IPs = 10.8.0.x.
- `minio-vault` Pod = Running.

## 5. LEDGER
Audit entry for Jan 28, 2026: Manual mesh recovery initiated following unauthorized mutation regression.


## 2026-01-29 — Network/Identity Hardening (Declaration-based)

### Authoritative Identity Enforcement (Talos)
- Every Talos machine config MUST set `machine.kubelet.extraArgs.node-ip: 10.8.0.x` (WireGuard mesh IP) so Node INTERNAL-IP is immutable.
- Do not rely on kubelet/CNI autodetection.

### CNI Device Pinning (Cilium)
- Cilium MUST bind to `devices: "wg0"` and talk to the API via `k8sServiceHost: "10.8.0.2"`.

### Protocol Discipline (ACCEP)
- No speculative toggling of Talos/Cilium/CoreDNS.
- Any mutation must be recorded here with a rollback note.

### Continuous Drift Detection
- Kyverno policy `law-network-integrity-v1` enforces Node INTERNAL-IP in `10.8.0.0/24`.

### SSOT Integrity
- Golden backup for Talos configs is maintained under `/opt/cryptophys/talos/configs/_golden` (read-only).
- Prefer surgical patching (`talosctl patch` / minimal diffs) over full-file overwrites.
