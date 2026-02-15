# Platform Deployment & SPIRE Integration Strategy

**Date**: 2026-02-15 00:36 UTC  
**Cluster**: cryptophys-genesis  
**Phase**: Production Platform Hydration

## Current State Analysis

### ✅ SPIRE Infrastructure Complete
- **SPIRE Server HA**: 3/3 replicas (PostgreSQL backend)
- **SPIRE Agents**: 5/5 DaemonSet (all nodes attested)
- **CSI Driver**: 5/5 DaemonSet (universal coverage)
- **Workload Registry**: 242 entries (44 unique identities)

### ⚠️ Cilium Encryption Status
```
Encryption: Disabled
Config: SPIRE socket paths configured
Volumes: ❌ No CSI volume mounted
```

**Analysis**:
- Cilium ConfigMap references SPIRE socket paths
- Cilium pods do NOT have SPIFFE CSI volume
- Encryption disabled (no WireGuard + SPIRE active yet)
- Current state: Bootstrap plaintext communication

**Decision**: **Defer Cilium SPIRE integration to Phase 2**
- Reason: Cilium is CNI layer, must remain stable during platform hydration
- Risk: Patching Cilium during platform deployment could disrupt networking
- Strategy: Deploy platform services first, then harden Cilium when stable

## Deployment Sequence (Production-Grade)

### Phase 1: GitOps Foundation (PRIORITY 1)
**Objective**: Establish declarative infrastructure management

**1.1 Gitea Deployment**
```bash
Namespace: platform-gitops
Identity: spiffe://cryptophys.work/platform-gitops/gitea
CSI Volume: ✓ Required
Dependencies: PostgreSQL (via CloudNativePG)
Ingress: gitea.cryptophys.work
```

**Configuration Requirements**:
- StatefulSet with SPIFFE CSI volume
- Persistent storage (Longhorn)
- PostgreSQL database
- SSH + HTTP/S access
- Webhooks for CI/CD

**1.2 Flux Bootstrap**
```bash
Namespace: platform-gitops
Identity: spiffe://cryptophys.work/platform-gitops/flux-*
Components: source-controller, kustomize-controller, helm-controller, notification-controller
CSI Volume: ✓ Required for all controllers
```

**Configuration Requirements**:
- Git repository source (Gitea)
- Kustomization resources
- HelmRelease CRDs
- Notification channels

**1.3 ArgoCD Deployment**
```bash
Namespace: platform-gitops
Identity: spiffe://cryptophys.work/platform-gitops/argocd-*
Components: server, repo-server, application-controller, dex-server, redis
CSI Volume: ✓ Required for all components
```

**Configuration Requirements**:
- Git repository integration
- SSO via Dex
- RBAC policies
- Application CRDs
- Ingress: argocd.cryptophys.work

### Phase 2: Secrets Management (PRIORITY 2)
**2.1 Vault Deployment**
```bash
Namespace: platform-vault
Identity: spiffe://cryptophys.work/platform-vault/vault
CSI Volume: ✓ Required
Mode: HA (3 replicas with Raft storage)
Authentication: SPIFFE (via Workload API)
```

**Integration Points**:
- SPIRE Workload API authentication
- Kubernetes auth backend
- KV secrets engine
- PKI secrets engine (CA for services)
- Transit engine (encryption as a service)

### Phase 3: Container Registry (PRIORITY 3)
**3.1 Harbor Deployment**
```bash
Namespace: registry
Identity: spiffe://cryptophys.work/registry/harbor-*
Components: core, portal, jobservice, registry, registryctl, trivy
CSI Volume: ✓ Required for all components
Storage: S3-compatible (MinIO) - Deploy first
```

**Configuration Requirements**:
- PostgreSQL database
- Redis cache
- S3 storage backend (MinIO)
- Image scanning (Trivy)
- Replication policies
- Ingress: harbor.cryptophys.work

### Phase 4: Storage & Backup (PRIORITY 3 - Before Harbor)
**4.1 MinIO Deployment**
```bash
Namespace: storage
Identity: spiffe://cryptophys.work/storage/minio
CSI Volume: ✓ Required
Mode: Distributed (4 nodes minimum)
```

**4.2 Velero Deployment**
```bash
Namespace: backup
Identity: spiffe://cryptophys.work/backup/velero
CSI Volume: ✓ Required
Backend: S3 (MinIO)
Schedule: Daily cluster backups
```

### Phase 5: Policy Enforcement (PRIORITY 4)
**5.1 Kyverno Deployment**
```bash
Namespace: kyverno
Identity: spiffe://cryptophys.work/kyverno/*
Components: admission-controller, background-controller, cleanup-controller, reports-controller
CSI Volume: ✓ Required
Mode: Audit (Non-blocking)
```

**Policies to Deploy**:
- Require SPIFFE CSI volume for all workloads
- Require resource limits
- Require labels (app, version, owner)
- Disallow privileged containers (exceptions: system namespaces)
- Require non-root user

**5.2 Gatekeeper Deployment**
```bash
Namespace: gatekeeper-system
Identity: spiffe://cryptophys.work/gatekeeper-system/*
Components: controller, audit
CSI Volume: ✓ Required
Mode: Audit (Non-blocking)
```

### Phase 6: Observability Stack (PRIORITY 5)
**6.1 Prometheus Stack**
```bash
Namespace: observability
Identity: spiffe://cryptophys.work/observability/prometheus-*
Components: server, alertmanager, pushgateway
CSI Volume: ✓ Required
```

**6.2 Grafana**
```bash
Namespace: observability
Identity: spiffe://cryptophys.work/observability/grafana
CSI Volume: ✓ Required
Ingress: grafana.cryptophys.work
```

**6.3 Loki + Promtail**
```bash
Namespace: observability
Identity: spiffe://cryptophys.work/observability/loki
CSI Volume: ✓ Required
```

**6.4 OpenTelemetry Collector**
```bash
Namespace: observability
Identity: spiffe://cryptophys.work/observability/otel-collector
CSI Volume: ✓ Required
```

**6.5 Headlamp**
```bash
Namespace: observability
Identity: spiffe://cryptophys.work/observability/headlamp
CSI Volume: ✓ Required
Ingress: headlamp.cryptophys.work
```

### Phase 7: CI/CD Pipeline (PRIORITY 6)
**7.1 Tekton Deployment**
```bash
Namespace: platform-tekton
Identity: spiffe://cryptophys.work/platform-tekton/*
Components: pipelines-controller, pipelines-webhook, triggers-controller, triggers-webhook
CSI Volume: ✓ Required
```

### Phase 8: Ingress & External Access (PRIORITY 7)
**8.1 Nginx Ingress Controller**
```bash
Namespace: ingress
Identity: spiffe://cryptophys.work/ingress/nginx-ingress-controller
CSI Volume: ✓ Required
LoadBalancer: MetalLB
TLS: Cert-manager + Let's Encrypt
```

**Ingress Routes to Create**:
- gitea.cryptophys.work → Gitea
- argocd.cryptophys.work → ArgoCD
- harbor.cryptophys.work → Harbor
- grafana.cryptophys.work → Grafana
- headlamp.cryptophys.work → Headlamp

## Phase 9: Cilium Hardening (FINAL PHASE)

### 9.1 Cilium SPIRE Integration
**Objective**: Enable transparent mTLS for all pod-to-pod traffic

**Current State**:
```yaml
# ConfigMap has SPIRE config but NOT USED
mesh-auth-spire-agent-socket: /run/spire/sockets/agent/agent.sock
mesh-auth-spire-server-address: spire-server.spire-system.svc.cluster.local:8081
```

**Required Changes**:
1. **Add CSI Volume to Cilium DaemonSet**:
   ```yaml
   volumes:
   - name: spiffe-workload-api
     csi:
       driver: csi.spiffe.io
       readOnly: true
   
   volumeMounts:
   - name: spiffe-workload-api
     mountPath: /run/spire/sockets
     readOnly: true
   ```

2. **Enable WireGuard + SPIRE Encryption**:
   ```yaml
   # Cilium ConfigMap
   enable-wireguard: "true"
   enable-wireguard-encryption: "true"
   mesh-auth-enabled: "true"
   mesh-auth-mutual-enabled: "true"
   mesh-auth-spiffe-trust-domain: "cryptophys.work"
   ```

3. **Grant Cilium Delegated Identity Permission**:
   ```yaml
   # SPIRE Agent ConfigMap
   authorized_delegates = [
     "spiffe://cryptophys.work/kube-system/cilium-agent"
   ]
   ```

4. **Restart Cilium Pods**:
   ```bash
   kubectl rollout restart daemonset/cilium -n kube-system
   ```

5. **Verify Encryption**:
   ```bash
   cilium status | grep Encryption
   # Expected: Encryption: Wireguard + SPIRE [✓]
   ```

**Risk Mitigation**:
- Perform during maintenance window
- Have console access to nodes (Talos Dashboard)
- Test on single node first (cordon others)
- Keep plaintext communication as fallback

### 9.2 Cleanup SPIRE Entries
**Objective**: Remove test/obsolete entries for performance

**Entries to Remove**:
- `mtls-test` namespace entries (test workloads)
- Any duplicate entries
- Obsolete service entries

**Script**:
```bash
# List all entries
kubectl exec -n spire-system spire-server-0 -- \
  /opt/spire/bin/spire-server entry show -selector k8s:ns:mtls-test

# Delete specific entry
kubectl exec -n spire-system spire-server-0 -- \
  /opt/spire/bin/spire-server entry delete -entryID <ID>
```

## SPIFFE CSI Volume Template

**For ALL Helm Deployments**:
```yaml
# values.yaml
extraVolumes:
  - name: spiffe-workload-api
    csi:
      driver: csi.spiffe.io
      readOnly: true

extraVolumeMounts:
  - name: spiffe-workload-api
    mountPath: /spiffe-workload-api
    readOnly: true
```

**For Manual Manifests**:
```yaml
spec:
  template:
    spec:
      volumes:
      - name: spiffe-workload-api
        csi:
          driver: csi.spiffe.io
          readOnly: true
      
      containers:
      - name: app
        volumeMounts:
        - name: spiffe-workload-api
          mountPath: /spiffe-workload-api
          readOnly: true
```

## Deployment Checklist

### Pre-Deployment
- [ ] Verify SPIRE infrastructure (13/13 pods running)
- [ ] Verify CSI driver (5/5 pods on all nodes)
- [ ] Verify workload registry (242 entries)
- [ ] Verify Longhorn storage (healthy)
- [ ] Verify MetalLB (IP pool available)

### Per-Service Deployment
- [ ] Add SPIFFE CSI volume to manifest
- [ ] Create namespace if not exists
- [ ] Deploy service (Helm/kubectl)
- [ ] Verify pods Running
- [ ] Verify identity issued (check logs)
- [ ] Verify service endpoints
- [ ] Create Ingress (if external access needed)
- [ ] Test functionality
- [ ] Document any issues

### Post-Deployment
- [ ] Verify all platform services running
- [ ] Verify GitOps synchronization
- [ ] Verify backup schedule
- [ ] Verify policy audit mode
- [ ] Verify observability dashboards
- [ ] Perform Cilium hardening
- [ ] Enable policy enforcement (after testing)

## Success Metrics

**Infrastructure**:
- 100% pods with SPIFFE identity
- 100% encrypted traffic (after Cilium hardening)
- 0 privileged containers (except system)
- 100% resources with limits
- 100% daily backups

**Operations**:
- GitOps-driven deployments (100%)
- Policy compliance rate (100% in audit mode)
- Mean time to recovery < 5 minutes
- Backup restore time < 15 minutes

**Security**:
- Zero trust: All services use mTLS
- No plaintext credentials
- Automated certificate rotation
- Audit logs for all operations

---
**Strategy Document**: 2026-02-15 00:36 UTC  
**Next Action**: Deploy Gitea with SPIFFE CSI integration
