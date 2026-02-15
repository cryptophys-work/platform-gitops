# High Availability Architecture: 3 Control Plane + 2 Worker Nodes

**Document Version:** 1.0  
**Date:** 2026-02-14  
**Cluster:** cryptophys-genesis  
**Environment:** Single-site, Talos Linux v1.12.0, Kubernetes v1.35.0

---

## Executive Summary

This document defines the HA architecture for a **5-node Kubernetes cluster** (3 control planes + 2 workers) running on Talos Linux with Longhorn storage in a **single-site deployment**.

**Key Constraint:** With only 2 worker nodes, strict pod anti-affinity for stateful workloads will fail. Therefore, **control plane nodes must be schedulable** for platform-tier services (Vault, SPIRE, Harbor, Gitea), while workers focus on application workloads.

**Design Philosophy:**
- Control planes = "Platform Nodes" (Tier-1/Tier-2 services)
- Workers = Application workloads
- Storage = Longhorn with 3-replica minimum
- Single-site limitations acknowledged with offsite backup strategy

---

## 1. Control Plane High Availability

### Quorum Design

**Configuration:**
- 3 control plane nodes: cortex, cerebrum, corpus
- etcd quorum: 2/3 nodes required
- Wireguard mesh for etcd communication (10.0.x.x subnet)

**Requirements:**
1. **API Server Endpoint:** Use VIP/Load Balancer (kube-vip on CP nodes) to provide single stable endpoint
   - Current: Direct endpoint to cortex (178.18.250.39:6443)
   - Target: VIP endpoint for failover
   
2. **etcd Backup:**
   - Scheduled snapshots (daily minimum)
   - Offsite storage (MinIO remote or S3-compatible)
   - Retention: 7 days local, 30 days offsite
   
3. **Controller Manager & Scheduler:**
   - Leader election enabled by default
   - All 3 instances active with automatic failover

**Failure Scenarios:**
- ✅ **1 CP node down:** Cluster continues operating (etcd quorum 2/3, API available)
- ❌ **2 CP nodes down:** Cluster loses quorum, control plane unavailable

---

## 2. Node Roles & Scheduling Policy

### Problem Statement

With only 2 worker nodes, strict `podAntiAffinity: requiredDuringSchedulingIgnoredDuringExecution` for 3-replica stateful workloads will fail. **Solution:** Allow platform workloads to schedule on control plane nodes.

### Node Labeling Strategy

**Control Plane Nodes (cortex, cerebrum, corpus):**
```yaml
node-role.kubernetes.io/control-plane: ""
cryptophys.io/tier: platform
```

**Worker Nodes (aether, campus):**
```yaml
cryptophys.io/tier: application
```

### Scheduling Rules

**Platform Workloads (Vault, SPIRE, Gitea, Harbor, PostgreSQL, Redis):**
```yaml
spec:
  nodeSelector:
    cryptophys.io/tier: platform
  
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app: <workload-name>
        topologyKey: kubernetes.io/hostname
  
  tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
```

**PodDisruptionBudget (Required):**
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: <workload>-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: <workload>
```

**Application Workloads:**
```yaml
spec:
  nodeSelector:
    cryptophys.io/tier: application
```

### Control Plane Taint Management

**Current State:** Check if CPs are tainted:
```bash
kubectl get nodes -o json | jq '.items[] | select(.metadata.labels["node-role.kubernetes.io/control-plane"]!="") | {name: .metadata.name, taints: .spec.taints}'
```

**Options:**
1. **Remove taint** (simpler, less secure):
   ```bash
   kubectl taint nodes cortex cerebrum corpus node-role.kubernetes.io/control-plane:NoSchedule-
   ```

2. **Keep taint + toleration** (recommended):
   - Keep `NoSchedule` taint on CPs
   - Add toleration only to platform namespace workloads
   - Better isolation, explicit policy

---

## 3. Storage: Longhorn as Critical Path

### Single-Site Storage Challenges

With single-site deployment, **storage plane is the primary SPOF**. Longhorn must be configured for maximum resilience within this constraint.

### Longhorn Configuration

**Replica Policy:**
```yaml
# For Tier-1 (Vault, SPIRE DB, etcd backups)
numberOfReplicas: 3
dataLocality: disabled  # Allow cross-node placement

# For Tier-2 (Gitea, Harbor registry cache)
numberOfReplicas: 3
dataLocality: disabled

# For Tier-3 (logs, ephemeral data)
numberOfReplicas: 2
dataLocality: best-effort
```

**Anti-Affinity Enforcement:**
```yaml
# Longhorn StorageClass
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-ha
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "3"
  staleReplicaTimeout: "30"
  replicaAutoBalance: "least-effort"
  nodeSelector: ""  # Allow all nodes
```

**Volume Placement:**
- Ensure replicas are distributed across 3+ nodes
- Monitor `longhorn volume list` for skewed replica placement
- Use Longhorn UI to verify replica distribution

### Backup Strategy

**Longhorn Backup Target:**
```yaml
# Option 1: MinIO distributed in-cluster (recommended)
backupTarget: s3://longhorn-backups@minio/
backupTargetCredentialSecret: minio-longhorn-secret

# Option 2: External S3 (offsite)
backupTarget: s3://backup-bucket@us-east-1/
```

**Backup Schedule:**
- **Tier-1 volumes:** Every 6 hours
- **Tier-2 volumes:** Daily
- **Retention:** 7 snapshots minimum

**Auto-Rebuild Settings:**
```yaml
# System settings
autoSalvage: true
autoDeletePodWhenVolumeDetachedUnexpectedly: true
replicaReplenishmentWaitInterval: 600  # 10 minutes
```

**Failure Scenarios:**
- ✅ **1 node storage failure:** Volume rebuilds on remaining nodes
- ⚠️ **2 replicas on same node (bad placement):** Risk of data loss if that node fails
- ❌ **2+ nodes simultaneous failure:** Potential data loss without offsite backup

---

## 4. Vault (Tier-1): Identity & Secrets

### HA Configuration

**Deployment:**
```yaml
replicas: 3
nodeSelector:
  cryptophys.io/tier: platform
tolerations:
- key: node-role.kubernetes.io/control-plane
  operator: Exists
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          app: vault
      topologyKey: kubernetes.io/hostname
```

**Storage Backend:**
```yaml
# Raft storage (recommended for single-site)
storage "raft" {
  path = "/vault/data"
  node_id = "${POD_NAME}"
  
  retry_join {
    leader_api_addr = "http://vault-0.vault-internal:8200"
  }
  retry_join {
    leader_api_addr = "http://vault-1.vault-internal:8200"
  }
  retry_join {
    leader_api_addr = "http://vault-2.vault-internal:8200"
  }
}
```

**Auto-Unseal:**
- **Option 1:** Transit auto-unseal (requires external Vault or KMS)
- **Option 2:** Shamir seal with breakglass procedure (manual unseal on restart)
  - Key shares: 5
  - Threshold: 3
  - Store shares in secure offline locations

**PodDisruptionBudget:**
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: vault-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: vault
```

**Failure Scenarios:**
- ✅ **1 CP node down:** Vault leader election, service continues
- ✅ **Raft disk corruption:** Restore from snapshot, rejoin cluster
- ⚠️ **Sealed state after restart:** Requires manual unseal (Shamir) or auto-unseal

---

## 5. SPIRE (Tier-1): Workload Identity

### Architecture

**SPIRE Server:**
```yaml
replicas: 3
nodeSelector:
  cryptophys.io/tier: platform
datastore: postgresql  # HA PostgreSQL cluster
```

**SPIRE Agent:**
```yaml
kind: DaemonSet
# Runs on all nodes (CP + workers)
```

### PostgreSQL HA for SPIRE

**Configuration:**
```yaml
# PostgreSQL cluster (Patroni or CloudNativePG)
replicas: 3
nodeSelector:
  cryptophys.io/tier: platform
storage:
  storageClass: longhorn-ha
  size: 10Gi
```

**Backup:**
- PITR (Point-In-Time Recovery) enabled
- WAL archiving to S3/MinIO
- Daily full backups
- Retention: 7 days

**PDB:**
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: postgresql-spire-pdb
spec:
  minAvailable: 2
```

**Failure Scenarios:**
- ✅ **1 DB replica down:** Automatic failover to standby
- ✅ **SPIRE server restart:** Agent reconnects automatically
- ⚠️ **All DB replicas down:** Restore from PITR backup

---

## 6. Gitea + Harbor (Tier-2): Source Control & Registry

### Shared vs Dedicated PostgreSQL

**Recommendation for 5-node cluster:**

**Single PostgreSQL HA cluster for platform services:**
- Gitea database
- Harbor database
- SPIRE database (if not separate)

**Benefits:**
- Reduced resource overhead
- Simplified backup/restore
- Easier maintenance

**Isolation:**
```sql
-- Separate databases
CREATE DATABASE gitea;
CREATE DATABASE harbor;
CREATE DATABASE spire;

-- Separate users with limited privileges
CREATE USER gitea_user WITH PASSWORD '...';
GRANT ALL ON DATABASE gitea TO gitea_user;
```

**Resource Limits:**
```yaml
# PostgreSQL container
resources:
  requests:
    memory: 4Gi
    cpu: 2
  limits:
    memory: 8Gi
    cpu: 4
```

### Redis HA for Harbor

**Configuration:**
```yaml
# Redis Sentinel for HA
replicas: 3
nodeSelector:
  cryptophys.io/tier: platform
```

**Harbor Services using Redis:**
- Session cache
- Job queue (jobservice)
- Chart cache

### Harbor Registry Storage: MinIO Distributed

**Problem:** Registry blobs on single PVC = SPOF

**Solution:** MinIO distributed mode

**MinIO Deployment:**
```yaml
# Minimum 4 pods for distributed erasure coding
replicas: 4
# Recommended: 4-6 pods across 3 CP + 1-2 workers

nodeSelector:
  cryptophys.io/tier: platform

volumeClaimTemplate:
  storageClassName: longhorn-ha
  size: 100Gi  # Per pod
```

**Harbor Configuration:**
```yaml
# Harbor registry storage
storage:
  type: s3
  s3:
    region: us-east-1
    bucket: harbor-registry
    endpoint: http://minio.storage.svc.cluster.local:9000
    secure: false
```

**Alternative (Not Recommended):**
- Longhorn RWX/NFS gateway → Single point of failure
- Object storage is more robust

### HA Replicas

**Gitea:**
```yaml
replicas: 2
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          app: gitea
      topologyKey: kubernetes.io/hostname
```

**Harbor Components:**
```yaml
# Core
core:
  replicas: 2
  
# Registry
registry:
  replicas: 2
  
# Job Service
jobservice:
  replicas: 2
  
# Trivy (optional)
trivy:
  replicas: 1
```

**PDBs Required for All:**
```yaml
minAvailable: 1  # For 2-replica services
```

**Failure Scenarios:**
- ✅ **1 Gitea pod down:** Load balancer redirects to healthy pod
- ✅ **1 MinIO pod down:** Distributed erasure coding maintains availability
- ✅ **Registry pod restart:** Image pulls continue via other replica
- ⚠️ **PostgreSQL cluster down:** All services unavailable until restore

---

## 7. Dependency Order & Bootstrap Sequence

### Cold Start Dependency Chain

**Critical Path for cluster recovery:**

```
1. Infrastructure Layer
   ├── Longhorn (storage)
   ├── CoreDNS
   └── CNI (Cilium)

2. Storage Backend
   └── MinIO (distributed)

3. Data Layer
   ├── PostgreSQL HA
   └── Redis HA

4. Identity Layer (Tier-1)
   ├── Vault
   └── SPIRE

5. Platform Services (Tier-2)
   ├── Harbor
   └── Gitea

6. Application Layer
   └── User workloads
```

### Circular Dependency Prevention

**Problem:** Vault needs image from Harbor, but Harbor needs secret from Vault

**Solution: Golden Images**

Store critical component images in multiple locations:

1. **Primary:** Harbor registry (normal operations)
2. **Bootstrap:** Public registry fallback (docker.io, ghcr.io, quay.io)
3. **Node cache:** Pre-pulled images on control plane nodes

**Implementation:**
```yaml
# Vault deployment
spec:
  template:
    spec:
      initContainers:
      - name: ensure-image
        image: ghcr.io/hashicorp/vault:1.14.0  # Public fallback
        command: ["/bin/true"]
      containers:
      - name: vault
        image: harbor.cryptophys.work/platform/vault:1.14.0  # Preferred
        imagePullPolicy: IfNotPresent  # Use cache if available
```

**Image Pre-pull for Bootstrap:**
```bash
# Pre-pull critical images on all CP nodes
talosctl -n cortex,cerebrum,corpus image pull \
  ghcr.io/hashicorp/vault:1.14.0 \
  ghcr.io/spiffe/spire-server:1.7.0 \
  docker.io/postgres:15-alpine \
  docker.io/redis:7-alpine \
  quay.io/minio/minio:latest
```

### Startup Readiness Probes

**Enforce dependency order via readiness:**

```yaml
# Harbor waiting for PostgreSQL
spec:
  containers:
  - name: core
    readinessProbe:
      exec:
        command:
        - /bin/sh
        - -c
        - pg_isready -h postgresql-ha.data.svc.cluster.local
      initialDelaySeconds: 30
      periodSeconds: 10
```

---

## 8. Minimum Viable HA Configuration

### Essential Components for 3CP + 2W

**Must-Have:**

1. **kube-vip** (API VIP)
   - Installation: [https://kube-vip.io/docs/installation/daemonset/](https://kube-vip.io/docs/installation/daemonset/)
   - VIP: Assign 1 IP from same subnet as control planes
   
2. **Longhorn** (replica=3, backup to MinIO)
   - Volume replica: 3
   - Backup target: MinIO S3
   - Schedule: Daily
   
3. **PostgreSQL HA** (3 replicas on CP)
   - Operator: CloudNativePG or Patroni
   - Replicas: 3
   - PITR enabled
   
4. **Vault Raft** (3 replicas on CP)
   - Storage: Raft integrated storage
   - Replicas: 3
   - Auto-unseal or breakglass procedure
   
5. **SPIRE** (3 server + agent DS)
   - Server replicas: 3
   - Agent: DaemonSet (all nodes)
   - Datastore: PostgreSQL HA
   
6. **Harbor HA** (registry → MinIO)
   - Core/Registry/JobService: 2 replicas each
   - Storage: MinIO distributed (4-6 pods)
   
7. **Gitea** (2 replicas)
   - Replicas: 2
   - Database: PostgreSQL HA
   - Git storage: Longhorn PVC

**Deployment Priority:**
```
Phase 1: Infrastructure (1-2 hours)
  - kube-vip
  - Longhorn
  - MinIO

Phase 2: Data Layer (1 hour)
  - PostgreSQL
  - Redis

Phase 3: Identity (30 min)
  - Vault
  - SPIRE

Phase 4: Platform (1 hour)
  - Harbor
  - Gitea
```

---

## 9. Single-Site Limitations & Mitigations

### What This Architecture Cannot Prevent

**Infrastructure Failures:**
- ❌ **Power outage** (entire site) → Total downtime
- ❌ **ISP outage** → External access lost
- ❌ **>1 node simultaneous hardware failure** → Quorum loss

**Data Loss Scenarios:**
- ❌ **Storage array failure** (if Longhorn uses same underlying storage)
- ❌ **Ransomware/corruption** without air-gapped backups
- ❌ **Operator error** (kubectl delete without confirmation)

### Mitigations Within Single-Site

**Power & Hardware:**
- UPS for all nodes (30-minute minimum runtime)
- Dual PSU with separate circuits
- Hardware monitoring (IPMI, out-of-band management)
- Spare hardware on-site

**Backup & Recovery:**
- **Offsite backup** (S3 remote, Wasabi, Backblaze)
  - Longhorn snapshots → S3
  - etcd snapshots → S3
  - PostgreSQL PITR → S3
  - Velero cluster backups → S3

- **Restore drills** (monthly)
  - Test cluster restore from backup
  - Measure RTO (Recovery Time Objective)
  - Document lessons learned

**Monitoring & Alerting:**
- Node down alerts (critical)
- Storage capacity (warning at 70%, critical at 85%)
- etcd health (latency, leader elections)
- Backup job failures (critical)
- Certificate expiration (warning at 30 days)

**Documentation:**
- Runbooks for all failure scenarios
- Break-glass procedures (Vault unseal, cluster bootstrap)
- Contact list (on-call rotation)

---

## 10. Implementation Checklist

### Pre-Deployment

- [ ] Label all nodes with `cryptophys.io/tier`
- [ ] Decide on CP taint policy (remove or tolerate)
- [ ] Provision VIP for kube-vip
- [ ] Prepare S3/MinIO credentials for backups

### Phase 1: Infrastructure

- [ ] Deploy kube-vip (API VIP)
- [ ] Update kubeconfig to use VIP endpoint
- [ ] Verify API failover (stop 1 apiserver)
- [ ] Deploy Longhorn (replica=3)
- [ ] Configure Longhorn backup target
- [ ] Deploy MinIO distributed (4+ pods)
- [ ] Verify MinIO erasure coding

### Phase 2: Data Layer

- [ ] Deploy PostgreSQL HA (3 replicas)
- [ ] Configure PITR backup
- [ ] Deploy Redis Sentinel (3 replicas)
- [ ] Verify DB failover

### Phase 3: Identity

- [ ] Deploy Vault (3 replicas, raft storage)
- [ ] Initialize Vault, store unseal keys
- [ ] Deploy SPIRE server (3 replicas)
- [ ] Deploy SPIRE agent (DaemonSet)
- [ ] Verify trust domain

### Phase 4: Platform

- [ ] Deploy Harbor (HA mode, MinIO storage)
- [ ] Configure Harbor with Trivy
- [ ] Push critical images to Harbor
- [ ] Deploy Gitea (2 replicas)
- [ ] Test git push/pull

### Phase 5: Validation

- [ ] PDB for all HA services
- [ ] Drain 1 CP node, verify workload migration
- [ ] Restart 1 MinIO pod, verify object availability
- [ ] Stop 1 PostgreSQL replica, verify failover
- [ ] Restore 1 PVC from Longhorn backup
- [ ] Restore cluster state from Velero backup

### Phase 6: Operations

- [ ] Document backup/restore procedures
- [ ] Set up monitoring dashboards
- [ ] Configure alerting rules
- [ ] Schedule restore drills (monthly)
- [ ] Review capacity planning (quarterly)

---

## Appendix A: Node Specifications

**Current Cluster:**
```
cortex (CP):     178.18.250.39, WG 10.0.3.176
cerebrum (CP):   157.173.120.200, WG 10.0.4.194
corpus (CP):     207.180.206.69, WG 10.0.2.218
aether (Worker): 212.47.66.101, WG 10.8.0.5
campus (Worker): 173.212.221.185, WG 10.8.0.6
```

**Talos Linux:**
- Version: v1.12.0
- Platform: Metal (Contabo VPS)
- Network: Wireguard mesh overlay

**Kubernetes:**
- Version: v1.35.0
- CNI: Cilium (to be installed)
- CSI: Longhorn v1.6.2

---

## Appendix B: Resource Estimation

**Control Plane Nodes (each):**
```
Reserved for platform services:
- Vault:       512Mi RAM, 0.5 CPU
- SPIRE:       256Mi RAM, 0.25 CPU
- PostgreSQL:  1.5Gi RAM, 0.5 CPU
- Redis:       512Mi RAM, 0.25 CPU
- Harbor:      2Gi RAM, 1 CPU
- Gitea:       1Gi RAM, 0.5 CPU
- MinIO:       2Gi RAM, 1 CPU

Total platform: ~8Gi RAM, 4 CPU
```

**Recommended CP node size:** 16Gi RAM, 8 CPU

**Worker Nodes (each):**
```
Available for applications:
- System overhead: 2Gi RAM, 1 CPU
- Application capacity: Remaining

Total capacity depends on workload
```

---

## Appendix C: Cost-Benefit Analysis

**Benefits of HA Configuration:**
- 🟢 Survive 1 node failure (any role)
- 🟢 Zero-downtime updates (rolling)
- 🟢 Predictable recovery (restore from backup)
- 🟢 Reduced MTTR (Mean Time To Recover)

**Costs:**
- 🔴 Increased complexity (more components)
- 🔴 Higher resource usage (3x for HA services)
- 🔴 Operational overhead (monitoring, maintenance)
- 🔴 Backup storage costs (S3/offsite)

**When to Accept Single Points of Failure:**
- Development/staging environments
- Non-critical workloads
- Budget constraints
- Acceptable downtime SLA (>1 hour)

**When HA is Mandatory:**
- Production environments
- Revenue-generating services
- Compliance requirements (SOC2, ISO27001)
- SLA <1 hour downtime

---

## Document History

| Version | Date       | Author  | Changes                        |
|---------|------------|---------|--------------------------------|
| 1.0     | 2026-02-14 | Copilot | Initial architecture document |

---

**Document Owner:** Platform Team  
**Review Cycle:** Quarterly  
**Next Review:** 2026-05-14
