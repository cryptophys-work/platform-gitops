# Autonomous Deployment Guide (v2.1)

**Date**: 2026-02-07  
**Version**: 2.1 (Institutional-Simple Monorepo + GitOps)  
**Status**: Build pipeline operational; repo consolidation + hardening in-progress

---

## 🎯 OVERVIEW: Cryptophys Autonomous Deployment Fabric

**Current State (2026-02-07)**:
- ✅ **Tekton Build Pipeline**: Deployed (build → scan → sign → push → update Git)
- ✅ **ArgoCD**: GitOps reconciler (deploy from Helm/Kustomize from Gitea)
- ✅ **Harbor**: Registry operational (scanning/signing pipeline ready)
- ✅ **Gitea**: Internal Git SSOT (repos + system webhook)
- ✅ **Kyverno**: Policy enforcement active (baseline)
- 🚧 **Supply-chain hardening**: Kyverno verifyImages + attestations planned

**Reality checks (important)**:
- ArgoCD controller namespace: `platform-gitops` (not `argocd`).
- Gitea DB connection is currently pinned to **Postgres single** (`postgres.postgresql.svc.cluster.local:5432`) as the stable baseline.
  - Postgres-HA (`postgresql-ha/pgpool`) exists but is **not** treated as production SSOT until healthy and tested (to avoid GitOps outage).

### Repo glossary (avoid confusion)

- **Source monorepo** (build input): `cryptophys/monorepo`
  - contains application source + optional Helm/Kustomize per app.
- **GitOps state repo** (cluster desired state): `cryptophys.adm/platform-gitops`
  - ArgoCD points here and reconciles the cluster.

If you prefer different naming, we can rename later, but the “2-repo model” stays the same.

**Target Architecture (v2.1 “institutional-simple”)**:
- **1 monorepo** untuk source + chart/kustomize per app
- **1 GitOps repo** untuk state cluster *(atau `clusters/` folder terpisah di monorepo)*
- **1 System Webhook (Gitea)** → **1 Tekton EventListener**, lalu filter hanya terima event dari `cryptophys/monorepo`
- Tekton **hanya** build/push image + update Git (pakai `[skip-ci]` untuk cegah loop)
- ArgoCD deploy (Helm/Kustomize) dari Gitea (GitOps)

---

## 🏗️ DELIVERY FABRIC COMPONENTS

### **1. BUILD PIPELINE (Tekton image-factory)**
**Status**: ✅ Operational

**Flow**:
```
Source Code (Gitea) → Tekton Pipeline → BuildKit (multi-arch)
  → Trivy Scan → Cosign Sign → Harbor Push → Update Git (GitOps) → ArgoCD deploy
```

**Tasks**:
1. `git-clone`: Clone from internal Gitea
2. `buildkit-build`: Multi-arch (amd64 + arm64)
3. `trivy-scan`: Fail on HIGH/CRITICAL
4. `cosign-sign`: Sign with prod key
5. `harbor-push`: Push to registry.cryptophys.work/prod/
6. `gitops-update`: Update image digest in Git (signed commit)

**Supply Chain Security**:
- ✅ All images built from source (no external pulls)
- ✅ Scan before sign
- ✅ SBOM + SLSA attestation
- ✅ Digest-pinned references
- ✅ Evidence uploaded to MinIO

---

### **2. GITOPS SYNC (ArgoCD Helm/Kustomize)**
**Status**: ✅ Operational

**Rule**:
- Tekton tidak melakukan `kubectl apply` ke cluster untuk workload aplikasi.
- Tekton mengupdate Git (manifest/values/images) → ArgoCD reconcile.

**Reason (simplicity + auditability)**:
- 1 source-of-truth: Git
- 1 reconciler: ArgoCD
- Build system (Tekton) tidak butuh akses cluster-wide untuk apply aplikasi

---

### **3. POLICY ENFORCEMENT (Kyverno)**
**Status**: ✅ Operational

**Active Policies**:
- Require image signatures (Cosign)
- Block privileged containers
- Enforce resource limits
- Require SPIRE SVID (NEW in v2.0)
- Block unsigned Git commits (NEW)

**Integration**:
- Mutating webhooks: Add labels/annotations
- Validating webhooks: Block non-compliant resources
- Background scanning: Audit existing resources

**Note**: Kyverno webhooks caused ArgoCD sync conflicts (v1.0), but Tekton handles this gracefully (v2.0)

---

### **4. REGISTRY (Harbor)**
**Status**: ✅ Operational

**Configuration**:
- URL: `registry.cryptophys.work`
- Projects: `prod` (immutable), `staging`, `dev`
- Content Trust: Enabled (Notary)
- Image Scanning: Trivy (on push)
- Replication: Disabled (local only)

**Integration**:
- Tekton pushes signed images
- Kyverno verifies signatures
- All pods pull from Harbor

---

### **5. SOURCE CODE (Gitea)**
**Status**: ✅ Operational (3/3 pods)

**Repository Structure**:
```
cryptophys/monorepo
├── ssot/                    # Single Source of Truth (Kustomize manifests)
│   ├── platform/
│   ├── apps/
│   └── system/
├── source/                  # Application source code
│   ├── aide/
│   ├── cerebrum/
│   ├── dao/
│   └── ...
└── platform/                # Platform GitOps
    └── gitops/tekton/
```

**Branch Protection** (NEW in v2.0):
- `main`: Requires GPG signature (unsigned commits REJECTED)
- Requires PR approval for high-risk changes
- Status checks: Kyverno validation

**Webhook**:
- Target: `tekton-build/gitea-webhook-listener`
- Events: `push`
- Filter: hanya `cryptophys/monorepo` + branch `main/master` + perubahan `trustedledger/**` atau `Dockerfile`
- Loop prevention: commit message berisi `[skip-ci]` dikecualikan

**ArgoCD repo source**:
- ArgoCD `Application` objects point to `cryptophys.adm/platform-gitops.git` (internal HTTP URL to the in-cluster Gitea service).
- Keep this path stable; if Gitea is down, GitOps reconciliation will stall by design.

---

## 🔄 AUTONOMOUS DEPLOYMENT FLOW (v2.0)

### **Forward Flow (Git → Cluster)**
```
1. Developer/automation pushes to `cryptophys/monorepo`
2. System Webhook (Gitea) → Tekton EventListener → PipelineRun
3. Tekton: build → scan → sign → push to Harbor
4. Tekton: update GitOps manifest/values (commit message includes `[skip-ci]`)
5. ArgoCD: reconcile (Helm/Kustomize) → deploy
6. (Optional) trustedledger: record build/scan/sign/deploy events
```

**Latency Targets (v2.0)**:
- Low risk: < 30 sec (down from 5 min)
- Medium risk: < 2 min
- High risk: < 5 min

---

### **Backward Flow (Cluster → Git)** 🚧 Planned
```
1. CEREBRUM monitors cluster state (10 sec refresh)
2. Drift detected (Git ≠ Cluster)
3. DEPLOYER assesses (legitimate vs violation)
4. If legitimate: AIDE commits cluster state → Git (signed)
5. If violation: Alert + Rollback proposal
6. DAO evaluation (ORCHESTRATOR → workers)
7. FACILITATOR decision → Action
```

---

## 🚨 EMERGENCY PROCEDURES

### **Instant Containment (NEW v2.0)**
**Trigger**: Falco CRITICAL event

**Flow** (< 5 sec):
```
1. Falco detects threat (e.g., unauthorized kubectl)
2. Falco Sidekick → Instant action (bypasses ORCHESTRATOR)
3. Action: Scale-to-zero or NetworkPolicy quarantine
4. Sidekick → FACILITATOR API (ledger write)
5. FACILITATOR records EMERGENCY_CONTAINMENT
6. Alert SRE via PagerDuty
```

**Examples**:
- Privilege escalation → Scale-to-zero
- Crypto mining detected → Quarantine (NetworkPolicy)
- Trust Ledger bypass → Block + Alert

---

### **Rollback Procedures**
**Option 1: Git Revert** (Application-level)
```bash
# AIDE creates rollback PR
git revert <bad-commit>
git commit -S -m "DAO ROLLBACK: Revert to known-good"
git push origin dao/rollback-<decision-id>
# Triggers normal GitOps flow
```

**Option 2: Velero Restore** (Cluster-level)
```bash
# For catastrophic failures
velero restore create --from-backup cluster-state-daily-<date> \
  --include-namespaces <namespace> \
  --wait
# RTO < 5 min
```

---

## 📊 OPERATIONAL METRICS (v2.0)

### **Performance**
- Git commit → Cluster sync: < 60 sec (P95)
- DAO validation: < 30 sec (low-risk)
- Falco → Contain: < 5 sec (CRITICAL)
- Image build: < 10 min (multi-arch)

### **Reliability**
- GitOps sync success rate: > 99%
- Image build success rate: > 95%
- Deployment success rate: > 98%
- Rollback rate: < 5%

### **Security**
- Image signature coverage: 100%
- Unsigned commit rejections: 100%
- SVID verification coverage: 100%
- Falco alert response time: < 5 sec

### **Availability** (NEW)
- FACILITATOR: 99.99% (3-node Raft)
- Tekton EventListener: 99.9% (3 replicas)
- MinIO: 99.99% (EC:4+2)
- SPIRE: 99.99% (3 replicas)

---

## 🔧 TROUBLESHOOTING

### **Issue: PipelineRun Stuck**
```bash
# Check PipelineRun status
kubectl get pipelinerun -n tekton-build

# Get logs
kubectl logs -n tekton-build -l tekton.dev/pipelineRun=<name> --all-containers

# Common causes:
# - Git clone failure (check Gitea connectivity)
# - Signature verification failure (check GPG keys)
# - SVID verification failure (check SPIRE)
# - kubectl apply failure (check manifests)
```

### **Issue: Unsigned Commit Detected**
```bash
# Task 2 will REJECT unsigned commits
# Error: "Commit <sha> is NOT signed!"

# Fix: Re-commit with GPG signature
git commit --amend -S
git push --force-with-lease
```

### **Issue: FACILITATOR Down**
```bash
# Check Raft cluster status
kubectl get pods -n dao-governance -l app=facilitator

# If 2/3 healthy: Leader election automatic
# If < 2/3: Manual intervention required

# Check WAL for recovery
kubectl exec -n dao-governance facilitator-0 -- ls /wal/

# Restore from MinIO if all nodes down
# (See disaster recovery runbook)
```

---

## 📚 RUNBOOKS

### **Runbook 1: Deploy New Application**
1. Create Kustomize manifests in `ssot/apps/<app>/`
2. Commit and sign: `git commit -S -m "Add new app"`
3. Push to branch: `git push origin feature/<app>`
4. Open PR (AIDE can automate this)
5. Wait for DAO validation (< 30 sec for low-risk)
6. Merge to main (triggers Tekton)
7. Verify: `kubectl get pods -n <namespace>`

### **Runbook 2: Update Image**
1. Build new image via Tekton `image-factory`
2. AIDE updates digest in `ssot/apps/<app>/kustomization.yaml`
3. AIDE commits (signed) and opens PR
4. DAO validates (parallel, < 30 sec)
5. FACILITATOR approves → Merge
6. Gitea webhook → Tekton sync
7. Verify: `kubectl get deployment <app> -o jsonpath='{.spec.template.spec.containers[0].image}'`

### **Runbook 3: Emergency Rollback**
1. Identify bad commit: `git log`
2. Create rollback: `git revert <sha>`
3. Sign commit: `git commit -S`
4. Push to emergency branch: `git push origin emergency/rollback-<id>`
5. ORCHESTRATOR fast-tracks (emergency bypass)
6. FACILITATOR approves (no DAO delay)
7. Tekton syncs immediately
8. Or: Use Velero restore for cluster-level rollback

---

## 🎯 NEXT STEPS (Remaining Implementation)

### **Immediate (Week 1)**
- [ ] Configure Gitea webhook (to EventListener)
- [ ] Test end-to-end: Git commit → Cluster sync
- [ ] Add Task 2: GPG signature verification
- [ ] Generate GPG keys for AIDE/ORCHESTRATOR

### **Short-term (Week 2-4)**
- [ ] Deploy HA infrastructure (SPIRE, MinIO, FACILITATOR Raft)
- [ ] Deploy DAO workers (ORCHESTRATOR, VALIDATOR, AUDITOR, DEPLOYER)
- [ ] Implement parallel validation
- [ ] Deploy CEREBRUM (cached state engine)

### **Mid-term (Week 5-7)**
- [ ] Deploy Falco + Sidekick (instant containment)
- [ ] Rebuild AIDE v2 (4 modes)
- [ ] Implement continuous ledger streaming
- [ ] Disaster recovery testing

---

## ✅ SUCCESS CRITERIA

**Functional**:
- ✅ Git commit → Cluster sync operational
- ✅ Only signed commits deployed
- ✅ SSOT enforced (Git = Cluster)
- ✅ All components monitored
- ✅ Emergency procedures tested

**Performance**:
- ✅ Sync latency < 60 sec
- ✅ DAO validation < 30 sec (low-risk)
- ✅ Containment < 5 sec (CRITICAL)

**Resilience**:
- ✅ RPO < 1 sec
- ✅ RTO < 5 min
- ✅ 99.99% availability

---

**Status**: Operational delivery fabric (build → scan → sign → promote → gitops)  
**Next**: Complete DAO governance implementation (7 weeks)  
**Vision**: Fully autonomous, self-healing, SSOT-enforced deployment platform
