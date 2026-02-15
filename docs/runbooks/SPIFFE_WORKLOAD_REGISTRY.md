# SPIFFE Workload Identity Registry - Cryptophys Platform

**Date**: 2026-02-15 00:32 UTC  
**Cluster**: cryptophys-genesis  
**Trust Domain**: cryptophys.work  
**Nodes**: 5 (3 control-plane, 2 workers)

## Summary

✅ **Total SPIFFE Entries**: 242 registered  
✅ **Unique Workload Identities**: 44 components  
✅ **Coverage**: Universal (all workloads registered across all 5 nodes)

## Registration Strategy

**Universal Node Coverage**: Each workload identity is registered on all 5 nodes, allowing pods to be scheduled anywhere and immediately receive their SPIFFE identity.

**Pattern**: 5 entries per workload (one per node) using k8s_psat attestation

## Registered Workloads by Category

### 1. GitOps Stack (platform-gitops namespace)
**Entries**: 50 (10 components × 5 nodes)

| Component | SPIFFE ID | TTL |
|-----------|-----------|-----|
| Gitea | `spiffe://cryptophys.work/platform-gitops/gitea` | 2h |
| Flux Source Controller | `spiffe://cryptophys.work/platform-gitops/flux-source-controller` | 1h |
| Flux Kustomize Controller | `spiffe://cryptophys.work/platform-gitops/flux-kustomize-controller` | 1h |
| Flux Helm Controller | `spiffe://cryptophys.work/platform-gitops/flux-helm-controller` | 1h |
| Flux Notification Controller | `spiffe://cryptophys.work/platform-gitops/flux-notification-controller` | 1h |
| ArgoCD Server | `spiffe://cryptophys.work/platform-gitops/argocd-server` | 1h |
| ArgoCD Repo Server | `spiffe://cryptophys.work/platform-gitops/argocd-repo-server` | 1h |
| ArgoCD Application Controller | `spiffe://cryptophys.work/platform-gitops/argocd-application-controller` | 1h |
| ArgoCD Dex Server | `spiffe://cryptophys.work/platform-gitops/argocd-dex-server` | 1h |
| ArgoCD Redis | `spiffe://cryptophys.work/platform-gitops/argocd-redis` | 1h |

**Label Selector**: `k8s:pod-label:app:<component>`

### 2. Secrets Management (platform-vault namespace)
**Entries**: 10 (2 components × 5 nodes)

| Component | SPIFFE ID | TTL |
|-----------|-----------|-----|
| Vault Server | `spiffe://cryptophys.work/platform-vault/vault` | 2h |
| Vault Agent Injector | `spiffe://cryptophys.work/platform-vault/vault-agent-injector` | 1h |

### 3. Container Registry (registry namespace)
**Entries**: 30 (6 components × 5 nodes)

| Component | SPIFFE ID | TTL |
|-----------|-----------|-----|
| Harbor Core | `spiffe://cryptophys.work/registry/harbor-core` | 2h |
| Harbor Portal | `spiffe://cryptophys.work/registry/harbor-portal` | 1h |
| Harbor Job Service | `spiffe://cryptophys.work/registry/harbor-jobservice` | 1h |
| Harbor Registry | `spiffe://cryptophys.work/registry/harbor-registry` | 2h |
| Harbor Registry Controller | `spiffe://cryptophys.work/registry/harbor-registryctl` | 1h |
| Harbor Trivy Scanner | `spiffe://cryptophys.work/registry/harbor-trivy` | 1h |

### 4. Storage & Backup
**Entries**: 10 (2 components × 5 nodes)

| Component | SPIFFE ID | TTL | Namespace |
|-----------|-----------|-----|-----------|
| MinIO | `spiffe://cryptophys.work/storage/minio` | 2h | storage |
| Velero | `spiffe://cryptophys.work/backup/velero` | 1h | backup |

### 5. Policy Enforcement
**Entries**: 30 (6 components × 5 nodes)

#### Kyverno (kyverno namespace)
| Component | SPIFFE ID | TTL |
|-----------|-----------|-----|
| Admission Controller | `spiffe://cryptophys.work/kyverno/kyverno-admission-controller` | 1h |
| Background Controller | `spiffe://cryptophys.work/kyverno/kyverno-background-controller` | 1h |
| Cleanup Controller | `spiffe://cryptophys.work/kyverno/kyverno-cleanup-controller` | 1h |
| Reports Controller | `spiffe://cryptophys.work/kyverno/kyverno-reports-controller` | 1h |

**Selector**: `k8s:app.kubernetes.io/component:<component>`

#### Gatekeeper (gatekeeper-system namespace)
| Component | SPIFFE ID | TTL |
|-----------|-----------|-----|
| Controller | `spiffe://cryptophys.work/gatekeeper-system/gatekeeper-controller` | 1h |
| Audit | `spiffe://cryptophys.work/gatekeeper-system/gatekeeper-audit` | 1h |

### 6. Observability (observability namespace)
**Entries**: 40 (8 components × 5 nodes)

| Component | SPIFFE ID | TTL |
|-----------|-----------|-----|
| Prometheus Server | `spiffe://cryptophys.work/observability/prometheus-server` | 1h |
| Prometheus Alertmanager | `spiffe://cryptophys.work/observability/prometheus-alertmanager` | 1h |
| Prometheus Pushgateway | `spiffe://cryptophys.work/observability/prometheus-pushgateway` | 1h |
| Grafana | `spiffe://cryptophys.work/observability/grafana` | 1h |
| Loki | `spiffe://cryptophys.work/observability/loki` | 1h |
| Promtail | `spiffe://cryptophys.work/observability/promtail` | 1h |
| OTEL Collector | `spiffe://cryptophys.work/observability/otel-collector` | 1h |
| Headlamp | `spiffe://cryptophys.work/observability/headlamp` | 1h |

### 7. Security Scanning (security namespace)
**Entries**: 5 (1 component × 5 nodes)

| Component | SPIFFE ID | TTL |
|-----------|-----------|-----|
| Trivy Operator | `spiffe://cryptophys.work/security/trivy-operator` | 1h |

### 8. Networking
**Entries**: 15 (3 components × 5 nodes)

#### Cilium (kube-system namespace)
| Component | SPIFFE ID | TTL | Selector |
|-----------|-----------|-----|----------|
| Cilium Agent | `spiffe://cryptophys.work/kube-system/cilium-agent` | 1h | `k8s:k8s-app:cilium` |
| Cilium Operator | `spiffe://cryptophys.work/kube-system/cilium-operator` | 1h | `k8s:name:cilium-operator` |

#### Ingress (ingress namespace)
| Component | SPIFFE ID | TTL |
|-----------|-----------|-----|
| Nginx Ingress | `spiffe://cryptophys.work/ingress/nginx-ingress-controller` | 1h |

### 9. CI/CD (platform-tekton namespace)
**Entries**: 20 (4 components × 5 nodes)

| Component | SPIFFE ID | TTL |
|-----------|-----------|-----|
| Tekton Pipelines Controller | `spiffe://cryptophys.work/platform-tekton/tekton-pipelines-controller` | 1h |
| Tekton Pipelines Webhook | `spiffe://cryptophys.work/platform-tekton/tekton-pipelines-webhook` | 1h |
| Tekton Triggers Controller | `spiffe://cryptophys.work/platform-tekton/tekton-triggers-controller` | 1h |
| Tekton Triggers Webhook | `spiffe://cryptophys.work/platform-tekton/tekton-triggers-webhook` | 1h |

### 10. Service Mesh (linkerd namespace)
**Entries**: 15 (3 components × 5 nodes)

| Component | SPIFFE ID | TTL |
|-----------|-----------|-----|
| Linkerd Identity | `spiffe://cryptophys.work/linkerd/linkerd-identity` | 2h |
| Linkerd Destination | `spiffe://cryptophys.work/linkerd/linkerd-destination` | 1h |
| Linkerd Proxy Injector | `spiffe://cryptophys.work/linkerd/linkerd-proxy-injector` | 1h |

### 11. Test Workloads (mtls-test namespace)
**Entries**: 10 (2 components × 5 nodes)

| Component | SPIFFE ID |
|-----------|-----------|
| Backend | `spiffe://cryptophys.work/mtls-test/backend` |
| Client | `spiffe://cryptophys.work/mtls-test/client` |

## Registration Scripts

### Master Registration Script
**Location**: `/opt/cryptophys/register-all-workloads.sh`  
**Usage**: Registers all platform workloads across all nodes  
**Runtime**: ~2 minutes for complete registration

```bash
/opt/cryptophys/register-all-workloads.sh
```

### Verification Commands

**Total entries**:
```bash
kubectl exec -n spire-system spire-server-0 -- \
  /opt/spire/bin/spire-server entry show | grep -c "Entry ID"
```

**Entries by namespace**:
```bash
kubectl exec -n spire-system spire-server-0 -- \
  /opt/spire/bin/spire-server entry show -selector k8s:ns:<namespace>
```

**Unique workload identities**:
```bash
kubectl exec -n spire-system spire-server-0 -- \
  /opt/spire/bin/spire-server entry show | grep "^SPIFFE ID" | sort -u
```

## Deployment Requirements

### For Each Platform Service

**1. Add SPIFFE CSI volume to manifest**:
```yaml
volumes:
- name: spiffe-workload-api
  csi:
    driver: csi.spiffe.io
    readOnly: true

volumeMounts:
- name: spiffe-workload-api
  mountPath: /spiffe-workload-api
  readOnly: true
```

**2. Application accesses Workload API**:
- Socket path: `/spiffe-workload-api/agent/agent.sock`
- Use SPIFFE SDK (Go, Java, Rust, Python)
- Fetch X.509-SVID automatically
- Establish mTLS connections

**3. Identity is issued immediately** (already registered)

## Security Architecture

```
┌─────────────────────────────────────────────────────┐
│  Application Pod (e.g., Gitea)                      │
│  ┌───────────────────────────────────────────────┐  │
│  │  spiffe://cryptophys.work/platform-gitops/    │  │
│  │              gitea                            │  │
│  │                                               │  │
│  │  /spiffe-workload-api/agent/agent.sock ──────┼──┼──> CSI Mount
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
                        │
                        │ Workload API (gRPC)
                        ▼
┌─────────────────────────────────────────────────────┐
│  SPIRE Agent (DaemonSet on Node)                    │
│  - Authenticates workload via k8s selectors         │
│  - Issues X.509-SVID (1h TTL, auto-rotates)         │
│  - CA chain: 3 certificates (HA verification)       │
└─────────────────────────────────────────────────────┘
                        │
                        │ Registration Lookup
                        ▼
┌─────────────────────────────────────────────────────┐
│  SPIRE Server HA (3 replicas + PostgreSQL)          │
│  - 242 entries registered                           │
│  - 44 unique workload identities                    │
│  - Universal node coverage                          │
└─────────────────────────────────────────────────────┘
```

## Benefits Achieved

✅ **Zero Trust Identity**: Every platform service has cryptographic identity  
✅ **Automatic Rotation**: X.509-SVIDs rotate every hour automatically  
✅ **Universal Coverage**: Workloads can run on any node  
✅ **mTLS Ready**: Applications can establish mutual TLS immediately  
✅ **Audit Trail**: All identity issuance logged by SPIRE  
✅ **Production Grade**: HA infrastructure with PostgreSQL backend

## Next Phase: Service Deployment

All platform services are **pre-registered** and ready for deployment:

1. **GitOps Stack** → Deploy Gitea, Flux, ArgoCD
2. **Vault** → Deploy with SPIFFE authentication
3. **Harbor** → Container registry with identity
4. **MinIO + Velero** → Storage and backup
5. **Kyverno + Gatekeeper** → Policy enforcement (audit mode)
6. **Observability** → Prometheus, Grafana, Loki, OTEL
7. **Tekton** → CI/CD pipelines
8. **Ingress** → External access with mTLS

**Pattern**: Add CSI volume → Deploy → Identity issued automatically

---
**Registry Complete**: 2026-02-15 00:32 UTC  
**Ready for**: Production Platform Deployment
