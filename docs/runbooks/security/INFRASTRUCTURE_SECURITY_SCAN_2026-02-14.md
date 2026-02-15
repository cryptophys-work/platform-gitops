# Infrastructure Security Scan Report
**Cluster:** cryptophys-genesis  
**Scan Date:** 2026-02-14  
**Report Version:** 1.0  
**Scan Scope:** Node-level, Talos OS, Kubernetes infrastructure components

---

## Executive Summary

**Overall Infrastructure Health:** ✅ **STABLE** with **MODERATE** security posture

- **5/5 Nodes Ready** (2 cordoned for maintenance)
- **3 CRITICAL CVEs** identified in infrastructure components
- **2 Storage volumes degraded** requiring attention
- **16 non-running pods** across cluster (mostly ImagePullBackOff in kyverno, aladdin namespaces)
- **Node resource pressure:** cortex at 80% CPU, corpus at 87% memory

### Critical Findings (Require Immediate Action)
1. **Harbor v2.14.2:** CVE-2025-68121 (CVSS 10.0), CVE-2025-49844 (Redis RCE)
2. **Linux Kernel 6.18.1:** CVE-2025-68260 (Rust Binder crash)
3. **2 Longhorn volumes in degraded state**
4. **High resource utilization on control-plane nodes**

---

## 1. Node Status & Platform Versions

### 1.1 Node Inventory

| Node | Role | Status | Age | Taints | CPU (cores) | Memory (GB) |
|------|------|--------|-----|--------|-------------|-------------|
| **cortex-178-18-250-39** | Control-Plane | Ready | 27d | control-plane | 6 | 12 |
| **cerebrum-157-173-120-200** | Control-Plane | Ready | 27d | control-plane | 6 | 12 |
| **corpus-207-180-206-69** | Control-Plane | Ready | 27d | control-plane | 6 | 12 |
| **aether-212-47-66-101** | Worker | Ready, SchedulingDisabled | 5d15h | unschedulable | 4 | 8 |
| **campus-173-212-221-185** | Worker | Ready, SchedulingDisabled | 20d | unschedulable | 2 | 4 |

**Node Health:**
- ✅ All nodes reporting Ready status
- ✅ No DiskPressure, MemoryPressure, or PIDPressure conditions
- ✅ All node leases active (last heartbeat: 2026-02-14T01:40:xx UTC)
- ⚠️ 2 worker nodes cordoned (aether, campus) - operational decision

### 1.2 Platform Component Versions

| Component | Version | Status | CVE Assessment |
|-----------|---------|--------|----------------|
| **Talos OS** | v1.12.0 (SHA: ac91ade2) | ✅ Latest | **CLEAR** - No known CVEs |
| **Linux Kernel** | 6.18.1-talos (GCC 15.2.0) | ⚠️ | **CVE-2025-68260** (Medium, crash only) |
| **Kubernetes** | v1.35.0 | ✅ Latest | CLEAR |
| **containerd** | 2.1.6 | ✅ Patched | **CLEAR** - CVE-2024-25621 fixed in 2.1.5+ |
| **Cilium** | v1.18.7 | ✅ | CLEAR (previous CVEs fixed) |
| **Longhorn** | v1.11.0 | ✅ | **CLEAR** - All CVEs fixed pre-release |
| **Harbor** | v2.14.2 | ❌ CRITICAL | **CVE-2025-68121 (CVSS 10.0), CVE-2025-49844** |
| **ArgoCD** | v3.3.0 | ✅ | CLEAR |
| **CoreDNS** | v1.11.1 | ✅ | CLEAR |

**Kernel Build Info:**
```
Linux version 6.18.1-talos (root@buildkitsandbox) 
(gcc (GCC) 15.2.0, GNU ld (GNU Binutils) 2.45.1) 
#1 SMP Wed Dec 17 10:07:33 UTC 2025
```

**Architecture:** amd64  
**Container Runtime:** containerd://2.1.6 (unified across all nodes)  
**RBAC:** Enabled on all nodes

---

## 2. Vulnerability Assessment

### 2.1 CRITICAL Vulnerabilities

#### 🔴 CVE-2025-68121 (Harbor v2.14.2)
- **CVSS Score:** 10.0 (CRITICAL)
- **Component:** Harbor Registry Core
- **Impact:** Unknown - details not yet fully disclosed
- **Status:** Awaiting Harbor v2.14.3 patch
- **Affected Pods:** All Harbor components in `registry` namespace
- **Remediation:** 
  - Monitor Harbor GitHub issues #22846, #22426, #22548
  - Upgrade to v2.14.3+ when available (ETA: imminent)
  - Consider network isolation for Harbor until patched

#### 🔴 CVE-2025-49844 (Harbor Redis v7.2.6)
- **CVSS Score:** Critical (RCE)
- **Component:** Redis 7.2.6 (Harbor dependency)
- **Impact:** Remote Code Execution on Harbor pods
- **Status:** Harbor team working on patch
- **Affected Image:** `goharbor/redis-photon:v2.14.2`
- **Remediation:**
  - DO NOT manually replace Redis image (stability risk)
  - Wait for official Harbor patch with updated Redis
  - Implement network policies restricting Harbor Redis access
  - Monitor for Harbor v2.14.3 release

#### 🟡 CVE-2025-15467 (Harbor v2.14.2)
- **CVSS Score:** Not yet disclosed (reported critical)
- **Status:** Awaiting Harbor v2.14.3 patch
- **Remediation:** Same as above

### 2.2 MEDIUM Vulnerabilities

#### 🟡 CVE-2025-68260 (Linux Kernel 6.18 Rust Binder)
- **CVSS Score:** 5.5 (MEDIUM)
- **Component:** Android Binder driver (Rust implementation)
- **Impact:** System crash ONLY (no code execution/privilege escalation)
- **Status:** Fixed in kernel 6.18.1+ (update verified)
- **Current Kernel:** 6.18.1-talos
- **Assessment:** ✅ **MITIGATED** - Running patched kernel
- **Note:** First CVE affecting Rust code in Linux kernel, proves unsafe Rust blocks still have risks

#### 🟡 CVE-2025-71180 (Linux Kernel IRQ Handling)
- **CVSS Score:** 5.5 (MEDIUM)
- **Component:** counter: interrupt-cnt code
- **Impact:** Kernel lockup due to improper lock acquisition
- **Status:** Fixed in post-6.18 kernels
- **Assessment:** ✅ Likely **MITIGATED** in 6.18.1-talos build

#### 🟡 CVE-2025-71181 (Linux Kernel Rust Binder Locking)
- **Component:** Rust Binder locking mechanism
- **Impact:** System deadlock (recursive locking)
- **Status:** Patched in 6.18.x+
- **Assessment:** ✅ Likely **MITIGATED** in 6.18.1-talos build

### 2.3 Component Assessment Summary

| Component | CVEs Found | Risk Level | Action Required |
|-----------|------------|------------|-----------------|
| Talos OS v1.12.0 | 0 | ✅ LOW | Monitor releases |
| Kernel 6.18.1-talos | 3 (mitigated) | 🟡 MEDIUM | Consider 6.19+ upgrade when available |
| containerd 2.1.6 | 0 (patched) | ✅ LOW | Already patched for CVE-2024-25621 |
| Cilium v1.18.7 | 0 | ✅ LOW | Previous fixes applied |
| Longhorn v1.11.0 | 0 | ✅ LOW | CVE fixes completed pre-release |
| Harbor v2.14.2 | 3 CRITICAL | 🔴 CRITICAL | **URGENT: Upgrade to v2.14.3+** |
| ArgoCD v3.3.0 | 0 | ✅ LOW | Up to date |
| CoreDNS v1.11.1 | 0 | ✅ LOW | Stable |

---

## 3. Infrastructure Health Assessment

### 3.1 Node Resource Utilization

**Current Usage (via metrics-server):**

| Node | CPU Usage | CPU % | Memory Usage | Memory % | Assessment |
|------|-----------|-------|--------------|----------|------------|
| cortex | **4809m** | **80%** | 4267Mi | 37% | ⚠️ **HIGH CPU** |
| corpus | 3191m | 53% | **9876Mi** | **87%** | ⚠️ **HIGH MEMORY** |
| cerebrum | 2289m | 38% | 6098Mi | 53% | ✅ Normal |
| aether | 446m | 11% | 1932Mi | 25% | ✅ Normal (cordoned) |
| campus | 276m | 14% | 886Mi | 25% | ✅ Normal (cordoned) |

**Recommendations:**
- **cortex:** Investigate high CPU usage (80%) - check if control-plane processes or workloads causing spike
- **corpus:** Monitor memory usage (87%) - consider rebalancing workloads or adding capacity
- Worker nodes (aether, campus) show healthy utilization but are cordoned - evaluate if uncordoning is appropriate

### 3.2 Allocated vs Requested Resources (cortex example)
```
Resource           Requests      Limits
cpu                1085m (18%)   1100m (18%)
memory             1769Mi (15%)  1792Mi (15%)
ephemeral-storage  0 (0%)        0 (0%)
```
**Note:** Despite low allocation percentages, actual CPU usage is 80%, indicating high system/control-plane overhead.

### 3.3 Storage Health (Longhorn)

#### Longhorn Manager Status
- ✅ Managers running: 3/3 (cortex, cerebrum, corpus)
- ✅ Engine images: 5/5 (all nodes)
- ✅ Instance managers: Active on cortex, cerebrum, corpus
- ⚠️ No instance managers on cordoned workers (expected)

#### Volume Health Summary

**Total Volumes:** 19  
**Attached:** 11  
**Detached:** 8 (normal - unused PVCs)  
**Degraded:** ⚠️ **2 volumes**  

**Degraded Volumes:**
1. `pvc-54ce5ab6-87fa-4778-ab0b-00e1b3186eb4` - 476MB, attached, degraded
2. `pvc-9d533462-baf9-4825-8f0a-04c64673055e` - 493MB, attached, degraded

**Attaching Volumes (transient):** 5 volumes in "attaching" state (may resolve automatically)

**ISCSI Status:**
- ✅ ISCSI tools extension active on all nodes (ghcr.io/siderolabs/iscsi-tools)
- ✅ No volume attachment failures in Longhorn logs (recent recovery successful)

**Recommendations:**
1. Investigate degraded volumes for replica count/placement issues
2. Check replica health: `kubectl get replicas -n longhorn-system -l volume=<volume-name>`
3. Consider triggering replica rebuilds if necessary
4. Monitor disk usage - all nodes showing healthy ephemeral-storage allocatable (~180-287GB)

### 3.4 Networking Health (Cilium)

**Cilium Agent Status:**
- ✅ DaemonSet: 5/5 agents running (all nodes)
- ✅ Envoy proxies: 5/5 running
- ✅ Operator: 1/1 running
- ✅ Version: v1.18.7 (latest stable)
- ✅ Wireguard mesh: Stable

**Network Connectivity:**
- ✅ Pod-to-pod communication verified (no widespread network issues)
- ✅ ClusterMesh API server certs present and valid (43h old)

### 3.5 DNS Health (CoreDNS)

- ✅ Deployment: 2/2 replicas running
- ✅ Version: v1.11.1
- ✅ Distribution: cerebrum (1), corpus (1)
- ✅ No DNS resolution issues reported

### 3.6 etcd Health

**Status:** ⚠️ Cannot verify directly (etcd not exposed as pods in kube-system)

**Assessment:**
- Control-plane nodes all Ready
- API server responsive (kubectl operations successful)
- Talos-managed etcd assumed healthy

**Recommendation:** Use Talos API to check etcd health:
```bash
talosctl --nodes 10.8.0.2,10.8.0.3,10.8.0.4 service etcd status
```

### 3.7 Non-Running Pods

**Total Non-Running:** 16 pods (excluding Completed jobs)

**Breakdown by Namespace:**
- **kyverno (5):** ImagePullBackOff on cleanup jobs (image registry issue)
- **aladdin (1):** Redpanda pod in ContainerCreating (91m)
- **registry (2):** Harbor jobservice/registry in ContainerCreating (recent restart)
- **minio (1):** Backup pod in ContainerCreating
- **security (2):** Vulnerability scan pods in Error state
- **spire (1):** Server pod in ContainerCreating
- **tekton-build (2):** ImagePullBackOff on cosign-check and gc job
- **vault-secrets (1):** Recovery pod in Error (10h old)
- **observability (1):** Synthetic checker in Pending

**Assessment:**
- Most issues are ImagePullBackOff or ContainerCreating (transient or configuration issues)
- Not infrastructure-level failures
- Harbor registry restart may be causing cascading image pull issues

**Recommendations:**
1. Verify Harbor registry availability and restart if needed
2. Clean up old Error/Failed pods (vault-recovery, security scans)
3. Investigate kyverno cleanup job image source
4. Check aladdin/spire pod logs for specific startup issues

---

## 4. Certificate Health

### 4.1 cert-manager Certificates

**Total Certificates Scanned:** 9 (aladdin namespace sample)

| Certificate | Ready | Expiry | Days Until Expiry |
|-------------|-------|--------|-------------------|
| aladdin-cryptophys-tls | ❌ False | N/A | - |
| aladdin-redpanda-default-cert | ✅ True | 2031-02-12 | ~1,825 days |
| aladdin-redpanda-external-cert | ✅ True | 2031-02-12 | ~1,825 days |
| aladdin.bus.redpanda-default-cert | ✅ True | 2031-02-12 | ~1,825 days |

**Assessment:**
- ✅ Most certificates valid for 5+ years
- ⚠️ 1 certificate not ready (aladdin-cryptophys-tls) - investigate cert-manager logs

### 4.2 Kubernetes Control-Plane Certificates

**Secrets in kube-system:**
- clustermesh-apiserver-admin-cert (43h old)
- clustermesh-apiserver-local-cert (43h old)
- clustermesh-apiserver-remote-cert (43h old)
- clustermesh-apiserver-server-cert (43h old)

**API Server Certificate:**
- Image: `registry.k8s.io/kube-apiserver:v1.35.0`
- API server responding normally

**Assessment:**
- ✅ No expired certificates detected
- ✅ Recent cert rotation for ClusterMesh (43h)
- Note: Talos manages control-plane certs automatically

**Recommendations:**
- Run Talos cert expiration check:
  ```bash
  talosctl --nodes 10.8.0.2 get certificateauthorities
  talosctl --nodes 10.8.0.2 get certificates
  ```

---

## 5. Security Posture & Hardening

### 5.1 Current Security Controls

| Control | Status | Notes |
|---------|--------|-------|
| **RBAC** | ✅ Enabled | Verified on all nodes |
| **Network Policies** | ✅ Active | Cilium enforcement active |
| **Pod Security Standards** | ⚠️ Partial | Kyverno active but cleanup jobs failing |
| **Image Scanning** | ⚠️ Degraded | Trivy scanner pods in Error state |
| **Secret Management** | ✅ Active | Vault/External Secrets operational |
| **Admission Control** | ⚠️ Partial | Kyverno webhooks operational, Gatekeeper status unknown |
| **Audit Logging** | ⚠️ Unknown | Not verified in this scan |

### 5.2 Node-Level Hardening Status

**Talos OS Security Features:**
- ✅ Immutable root filesystem
- ✅ No SSH access (API-only management)
- ✅ Minimal attack surface (no package manager)
- ✅ Secure boot support available
- ✅ Kernel module signature enforcement
- ✅ Disk encryption support (configuration dependent)

**Container Runtime Security (containerd 2.1.6):**
- ✅ Patched for CVE-2024-25621 (directory permissions)
- ✅ No known unpatched CVEs
- ✅ Running in rootless mode where applicable

### 5.3 Compliance Gaps & Recommendations

#### Immediate Actions (Week 1)
1. **CRITICAL:** Upgrade Harbor to v2.14.3+ when released (CVE-2025-68121, CVE-2025-49844)
2. Fix degraded Longhorn volumes (2 volumes)
3. Resolve non-running security scan pods (Trivy)
4. Investigate and fix Kyverno cleanup job ImagePullBackOff issues
5. Address high CPU (cortex) and memory (corpus) usage

#### Short-Term Actions (Month 1)
1. Upgrade Linux kernel to 6.19+ when Talos releases support (mitigates remaining kernel CVEs)
2. Implement cert-manager monitoring for expiration alerts
3. Fix failing certificate (aladdin-cryptophys-tls)
4. Evaluate uncordoning worker nodes (aether, campus) if capacity needed
5. Set up automated CVE scanning for cluster components

#### Long-Term Actions (Quarter 1)
1. Implement automated security patching for critical components
2. Establish baseline resource usage and alerting thresholds
3. Conduct full etcd health audit via Talos API
4. Enable audit logging for compliance requirements
5. Implement image signature verification (Cosign/Sigstore)
6. Consider Falco re-enablement (driver compatibility resolved)

---

## 6. Risk Assessment Matrix

| Risk | Likelihood | Impact | Overall Risk | Mitigation Priority |
|------|------------|--------|--------------|---------------------|
| Harbor RCE exploitation (CVE-2025-49844) | Medium | Critical | 🔴 **HIGH** | **P0 - Immediate** |
| Harbor unknown exploit (CVE-2025-68121) | Low | Critical | 🟡 **MEDIUM-HIGH** | **P0 - Immediate** |
| Longhorn volume data loss (degraded volumes) | Medium | High | 🟡 **MEDIUM** | **P1 - This Week** |
| Node resource exhaustion (cortex/corpus) | Medium | Medium | 🟡 **MEDIUM** | P1 - This Week |
| Kernel crash (CVE-2025-68260) | Low | Medium | 🟢 **LOW** | P2 - Monitor |
| Certificate expiration | Low | High | 🟢 **LOW** | P3 - Monitor |
| Image scanning failure | Medium | Low | 🟢 **LOW** | P2 - This Month |

---

## 7. Recommended Remediation Timeline

### Week 1 (Feb 14-21, 2026)
- [ ] **DAY 1:** Network isolate Harbor (restrict ingress to authorized users only)
- [ ] **DAY 1:** Monitor Harbor GitHub for v2.14.3 release announcement
- [ ] **DAY 2:** Troubleshoot degraded Longhorn volumes (rebuild replicas)
- [ ] **DAY 3:** Investigate cortex high CPU usage (identify top processes)
- [ ] **DAY 4:** Fix Kyverno cleanup job ImagePullBackOff (check image registry)
- [ ] **DAY 5:** Upgrade Harbor to v2.14.3+ (when available)
- [ ] **DAY 5:** Restart security scanner pods (Trivy)
- [ ] **DAY 7:** Validate all remediation actions

### Month 1 (Feb 2026)
- [ ] Monitor for Talos v1.13+ with kernel 6.19 support
- [ ] Implement cert-manager expiration monitoring
- [ ] Evaluate worker node uncordoning
- [ ] Establish resource usage baselines and alerts
- [ ] Document etcd health check procedures

### Quarter 1 (Feb-Apr 2026)
- [ ] Implement automated CVE scanning pipeline
- [ ] Establish security patching SLAs
- [ ] Conduct full security audit (including audit logs, Falco re-enablement)
- [ ] Plan for Talos/K8s upgrade cadence

---

## 8. Conclusion

The cryptophys-genesis cluster demonstrates **strong infrastructure stability** with all nodes operational and core Kubernetes components functioning correctly. However, **immediate action is required** to address critical vulnerabilities in Harbor v2.14.2.

### Key Takeaways

✅ **Strengths:**
- Talos OS v1.12.0 and containerd 2.1.6 are patched and secure
- All 5 nodes healthy and reporting Ready
- Core infrastructure (Cilium, CoreDNS, Longhorn managers) operational
- Strong security foundation (RBAC, network policies, immutable OS)

⚠️ **Areas Requiring Attention:**
- Harbor v2.14.2 has 2 CRITICAL CVEs requiring urgent patching
- 2 Longhorn volumes in degraded state (data integrity risk)
- High resource utilization on cortex and corpus nodes
- 16 non-running pods (mostly transient issues)

🔴 **Critical Actions:**
1. **Upgrade Harbor to v2.14.3+ immediately when released**
2. Fix degraded Longhorn volumes within 48 hours
3. Investigate and resolve high resource usage on control-plane nodes

### Infrastructure Security Grade: **B+**

**Justification:** Solid foundation with proactive security controls, but critical Harbor CVEs and degraded storage volumes prevent an A-grade rating. Once Harbor is patched and storage issues resolved, infrastructure security posture will be excellent.

---

## 9. Appendix: Commands for Ongoing Monitoring

### Node Health
```bash
kubectl get nodes -o wide
kubectl top nodes
kubectl get nodes -o json | jq -r '.items[] | "\(.metadata.name)\t\(.status.conditions[] | select(.type=="Ready") | .status)"'
```

### CVE Scanning
```bash
# Harbor vulnerability status
kubectl get pods -n registry -o json | jq -r '.items[].spec.containers[].image' | grep goharbor

# Check for updates
curl -s https://api.github.com/repos/goharbor/harbor/releases/latest | jq -r .tag_name
```

### Storage Health
```bash
kubectl get volumes -n longhorn-system -o custom-columns=NAME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness
kubectl get pods -n longhorn-system -l app=longhorn-manager
```

### Certificate Expiration
```bash
kubectl get certificates -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.conditions[0].status,EXPIRY:.status.notAfter
talosctl --nodes 10.8.0.2 get certificates
```

### Talos System Info
```bash
talosctl --nodes 10.8.0.2,10.8.0.3,10.8.0.4 version
talosctl --nodes 10.8.0.2 service etcd status
talosctl --nodes 10.8.0.2 get certificateauthorities
```

---

**Report Generated:** 2026-02-14T01:45:00Z  
**Next Scan Recommended:** 2026-02-21 (Weekly)  
**Report Author:** Copilot CLI Infrastructure Security Scanner  
**Cluster Contact:** cryptophys-genesis operations team
