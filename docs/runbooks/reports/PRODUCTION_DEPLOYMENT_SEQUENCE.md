# PRODUCTION DEPLOYMENT SEQUENCE
## World-Class HA Genesis Bootstrap - Zero SPOF from Day 0

**Principles:**
- Production-Grade: No shortcuts, no "add later"
- Idempotent: Every step can be rerun safely
- Persistent: All state in replicated storage
- Deterministic: Same inputs → same outputs
- Zero SPOF: Full redundancy from genesis
- Anti-Fragile: Survives single node failure

**Cluster:** 3 CP (cortex, cerebrum, corpus) + 2 Workers (aether, campus)

---

## PHASE 0: FOUNDATION INFRASTRUCTURE ✅

**Status:** COMPLETE

### Step 1: Cilium CNI ✅
- Version: v1.16.5
- Mode: Native routing, Wireguard encryption
- HA: DaemonSet on all nodes

### Step 2: Control Plane HA ✅
- DNS Round-Robin: api.cryptophys.work → 3 CP IPs
- certSANs: api.cryptophys.work + individual IPs
- Redundancy: Any 1 CP failure tolerated

### Step 3: Node Labels & Taints ✅
- Control Planes: `cryptophys.io/tier=platform`
- Workers: `cryptophys.io/tier=application`
- Taint: `node-role.kubernetes.io/control-plane:NoSchedule`

### Step 4: Longhorn Storage ✅
- Version: v1.6.2
- Replicas: 3 (across CP nodes)
- ISCSI: Enabled on all 5 nodes
- Default StorageClass: `longhorn`

---

## PHASE 1: IDENTITY & SERVICE MESH FOUNDATION

### Step 5: PostgreSQL HA Cluster
**Purpose:** Database for SPIRE, Gitea, Harbor
**Operator:** CloudNativePG or Zalando PostgreSQL Operator

**Configuration:**
```yaml
instances: 3
scheduling:
  nodeSelector:
    cryptophys.io/tier: platform
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      effect: NoSchedule
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: DoNotSchedule

storage:
  storageClass: longhorn
  size: 20Gi
  
backup:
  method: WAL-G or pgBackRest
  destination: TBD (MinIO-velero after Step 9)
  
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi
```

**Redundancy:** 3 replicas, 1 primary + 2 replicas, auto-failover

**Databases to create:**
- `spire` (SPIRE Server backend)
- `gitea` (Gitea metadata)
- `harbor` (Harbor metadata)
- `registry` (Harbor registry layer)

**Verification:**
```bash
kubectl get pods -n postgresql-system
kubectl exec -n postgresql-system postgres-1 -- psql -U postgres -l
```

---

### Step 6: SPIRE Identity Foundation
**Purpose:** Workload identity for Linkerd, Vault, all services

**Components:**
- SPIRE Server: 3 replicas on CP nodes
- SPIRE Agent: DaemonSet on all nodes
- Backend: PostgreSQL (from Step 5)

**Configuration:**
```yaml
server:
  replicas: 3
  dataStore:
    sql:
      plugin_data:
        database_type: postgres
        connection_string: postgresql://spire@postgres-rw.postgresql-system:5432/spire
  
  nodeSelector:
    cryptophys.io/tier: platform
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      effect: NoSchedule

agent:
  nodeSelector: {}  # DaemonSet on ALL nodes
```

**Trust Domain:** `cryptophys.work`

**Verification:**
```bash
kubectl get pods -n spire-system
kubectl exec -n spire-system spire-server-0 -- \
  /opt/spire/bin/spire-server healthcheck
```

---

### Step 7: Linkerd Service Mesh
**Purpose:** mTLS, observability, traffic control

**Components:**
- Linkerd Control Plane: 3 replicas on CP nodes
- Linkerd Proxy: Injected into all meshed pods
- Identity: SPIRE integration (from Step 6)

**Configuration:**
```yaml
identity:
  issuer:
    scheme: kubernetes.io/tls

controlPlane:
  replicas: 3
  nodeSelector:
    cryptophys.io/tier: platform
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      effect: NoSchedule
      
proxy:
  resources:
    cpu:
      request: 100m
    memory:
      request: 64Mi
```

**Mesh Injection:**
- Annotate namespaces: `linkerd.io/inject: enabled`
- All platform services meshed from deployment

**Verification:**
```bash
linkerd check
linkerd viz stat deploy -n linkerd
```

---

## PHASE 2: INGRESS & LOAD BALANCING

### Step 8: Ingress Foundation

**8a: MetalLB (L2/BGP)**
```yaml
addresses:
  - 178.18.250.50-178.18.250.60  # 10 IP pool
  - 157.173.120.50-157.173.120.60
  - 207.180.206.50-207.180.206.60

mode: L2  # or BGP if routers support
```

**8b: Ingress NGINX**
```yaml
controller:
  kind: DaemonSet
  nodeSelector:
    cryptophys.io/tier: platform
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      effect: NoSchedule
  
  service:
    type: LoadBalancer
    loadBalancerIP: 178.18.250.50  # MetalLB pool
    
  replicas: 3  # DaemonSet on 3 CP nodes
```

**DNS Configuration:**
```
*.cryptophys.work → 178.18.250.50, 157.173.120.50, 207.180.206.50
```

**Verification:**
```bash
kubectl get svc -n ingress-nginx
curl -I https://test.cryptophys.work
```

---

## PHASE 3: BACKUP & OBJECT STORAGE

### Step 9a: MinIO-Velero (Backup Storage)
**Purpose:** Velero backup destination (self-contained)

**Configuration:**
```yaml
mode: distributed
replicas: 4  # 4 pods for erasure coding EC:2
spread: Across CP nodes + 1 worker

nodeSelector:
  cryptophys.io/tier: platform
  
storage:
  storageClass: longhorn
  size: 100Gi per pod
  
service:
  type: ClusterIP
  
ingress:
  enabled: true
  host: velero-minio.cryptophys.work
  tls: true
```

**Buckets:**
- `velero-backups` (cluster backups)
- `velero-postgres` (database backups)

**Backup Strategy:** Longhorn PVC replication (3x), NO Velero backup of itself

---

### Step 9b: Velero + External S3
**Purpose:** Cluster disaster recovery

**Dual Backend:**
```yaml
backupStorageLocations:
  - name: minio-internal
    provider: aws
    bucket: velero-backups
    config:
      region: minio
      s3ForcePathStyle: "true"
      s3Url: http://minio-velero.minio-velero:9000
  
  - name: s3-external
    provider: aws
    bucket: cryptophys-genesis-backups
    config:
      region: us-east-1  # or Wasabi region
```

**Schedule:**
```yaml
schedules:
  - name: daily-full
    schedule: "0 2 * * *"
    locations: [minio-internal, s3-external]
    
  - name: hourly-incremental
    schedule: "0 * * * *"
    locations: [minio-internal]
```

**Verification:**
```bash
velero backup-location get
velero schedule get
```

---

### Step 9c: MinIO-Apps (Application Object Storage)
**Purpose:** Harbor registry, application data

**Configuration:**
```yaml
mode: distributed
replicas: 4
spread: All 5 nodes (CP + Workers)

nodeSelector: {}  # Allow all nodes

storage:
  storageClass: longhorn
  size: 500Gi per pod
  
service:
  type: ClusterIP
  
ingress:
  enabled: true
  host: minio.cryptophys.work
  tls: true

velero:
  backup: true  # Backed up by Velero (from 9b)
```

**Buckets:**
- `harbor-registry` (container images)
- `harbor-chartmuseum` (Helm charts)
- `loki-chunks` (log storage)
- `tempo-traces` (trace storage)

---

### Step 9d: Redis HA
**Purpose:** Cache for Gitea, Harbor, sessions

**Configuration:**
```yaml
sentinel:
  enabled: true
  replicas: 3

master:
  persistence:
    storageClass: longhorn
    size: 10Gi

replica:
  replicaCount: 2
  persistence:
    storageClass: longhorn
    size: 10Gi

nodeSelector:
  cryptophys.io/tier: platform
tolerations:
  - key: node-role.kubernetes.io/control-plane
    effect: NoSchedule
```

**Mode:** Redis Sentinel (1 master + 2 replicas + 3 sentinels)

---

## PHASE 4: GITOPS FOUNDATION

### Step 10a: Gitea (Manual Deployment)
**Purpose:** Git source for Flux GitOps

**Configuration:**
```yaml
replicas: 3
database:
  type: postgres
  host: postgres-rw.postgresql-system
  name: gitea

cache:
  type: redis
  host: redis-master.redis-system

storage:
  type: minio
  endpoint: minio-apps.minio-apps:9000
  bucket: gitea-artifacts

nodeSelector:
  cryptophys.io/tier: platform
tolerations:
  - key: node-role.kubernetes.io/control-plane
    effect: NoSchedule

ingress:
  enabled: true
  host: git.cryptophys.work
  tls: true

linkerd:
  inject: enabled
```

**Post-Install:**
```bash
# Create admin user
kubectl exec -n gitea gitea-0 -- gitea admin user create \
  --username admin --password ... --email admin@cryptophys.work --admin

# Create organization & repo
curl -X POST https://git.cryptophys.work/api/v1/orgs \
  -H "Authorization: token ..." \
  -d '{"username": "platform"}'

curl -X POST https://git.cryptophys.work/api/v1/orgs/platform/repos \
  -d '{"name": "platform-gitops", "private": true}'
```

---

### Step 10b: Flux CD Bootstrap
**Purpose:** GitOps automation

**Bootstrap:**
```bash
flux bootstrap gitea \
  --owner=platform \
  --repository=platform-gitops \
  --branch=main \
  --path=clusters/genesis \
  --personal=false \
  --hostname=git.cryptophys.work \
  --token-auth
```

**Flux Components:**
- source-controller: Git repo watcher
- kustomize-controller: Kustomization applier
- helm-controller: HelmRelease manager
- notification-controller: Alert dispatcher

**Verification:**
```bash
flux check
flux get sources git
flux get kustomizations
```

---

### Step 10c: Gitea → Flux-Managed
**Purpose:** Self-hosting transition

**Process:**
1. Commit Gitea HelmRelease to `platform-gitops` repo
2. Flux reconciles and takes over management
3. Manual Helm release becomes Flux-managed

**HelmRelease:**
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: gitea
  namespace: gitea
spec:
  interval: 5m
  chart:
    spec:
      chart: gitea
      version: 10.x.x
      sourceRef:
        kind: HelmRepository
        name: gitea
  values:
    # Same values as manual install
```

---

### Step 10d: ArgoCD (Optional GitOps)
**Purpose:** Alternative/complementary GitOps engine

**Configuration:**
```yaml
controller:
  replicas: 3

server:
  replicas: 3
  ingress:
    host: argocd.cryptophys.work

repoServer:
  replicas: 3

applicationSet:
  replicas: 2

nodeSelector:
  cryptophys.io/tier: platform

linkerd:
  inject: enabled
```

**GitOps Strategy:**
- Flux: Infrastructure & platform services
- ArgoCD: Application deployments (optional)
- Or: Flux-only (simpler)

---

## PHASE 5: PLATFORM SERVICES (Flux-Managed)

All deployed via Flux HelmRelease in `platform-gitops` repo.

### Step 11: Vault
**Purpose:** Secrets management, PKI, encryption

**Configuration:**
```yaml
ha:
  enabled: true
  replicas: 3
  raft:
    enabled: true
    storage:
      storageClass: longhorn

unsealer:
  mode: auto
  backend: kubernetes

spire:
  integration: enabled

nodeSelector:
  cryptophys.io/tier: platform

ingress:
  enabled: true
  host: vault.cryptophys.work
```

---

### Step 12: Harbor Registry
**Purpose:** Container image & Helm chart registry

**Configuration:**
```yaml
database:
  type: external
  external:
    host: postgres-rw.postgresql-system
    database: harbor

redis:
  type: external
  external:
    addr: redis-master.redis-system:6379

storage:
  type: s3
  s3:
    endpoint: minio-apps.minio-apps:9000
    bucket: harbor-registry

trivy:
  enabled: true
  replicas: 2

replicas:
  core: 3
  portal: 3
  registry: 3

nodeSelector:
  cryptophys.io/tier: platform

ingress:
  core:
    host: harbor.cryptophys.work
  notary:
    host: notary.cryptophys.work
```

---

### Step 13: Tekton Pipelines
**Purpose:** CI/CD pipeline execution

**Configuration:**
```yaml
pipeline:
  replicas: 3

triggers:
  replicas: 3

dashboard:
  replicas: 2
  ingress:
    host: tekton.cryptophys.work

nodeSelector:
  cryptophys.io/tier: platform
```

---

### Step 14: Crossplane (Optional)
**Purpose:** Infrastructure as Code

**Configuration:**
```yaml
replicas: 3

providers:
  - provider-aws
  - provider-kubernetes

nodeSelector:
  cryptophys.io/tier: platform
```

---

## PHASE 6: POLICY & SECURITY (Audit Mode)

Deploy AFTER Vault and all platform services running.

### Step 15: Kyverno
**Purpose:** Kubernetes policy engine

**Configuration:**
```yaml
admissionController:
  replicas: 3
  failurePolicy: Ignore  # Audit mode

backgroundController:
  replicas: 2

reportsController:
  replicas: 2

policies:
  mode: audit  # No enforcement initially

nodeSelector:
  cryptophys.io/tier: platform
```

**Policies:**
- Require resource limits
- Disallow host namespaces
- Require read-only root filesystem
- Require non-root user
- Require pod security standards

---

### Step 16: Gatekeeper (OPA)
**Purpose:** Policy enforcement (audit mode)

**Configuration:**
```yaml
audit:
  replicas: 3
  auditInterval: 60

webhook:
  replicas: 3
  failurePolicy: Ignore  # Audit mode

nodeSelector:
  cryptophys.io/tier: platform
```

**Constraints:**
- Container resource limits
- Image from trusted registry
- No privileged containers
- Network policies required

---

## PHASE 7: OBSERVABILITY STACK

Deploy last to observe everything.

### Step 17: Prometheus + Thanos
**Purpose:** Metrics collection & long-term storage

**Configuration:**
```yaml
prometheus:
  replicas: 2
  retention: 15d
  storage:
    storageClass: longhorn
    size: 100Gi
  
  nodeSelector:
    cryptophys.io/tier: platform

thanos:
  query:
    replicas: 2
  
  storegateway:
    replicas: 2
  
  compactor:
    replicas: 1
  
  objstore:
    type: s3
    bucket: thanos-metrics
    endpoint: minio-apps.minio-apps:9000

ingress:
  host: prometheus.cryptophys.work
```

---

### Step 18: Loki
**Purpose:** Log aggregation

**Configuration:**
```yaml
loki:
  replicas: 3
  storage:
    type: s3
    s3:
      endpoint: minio-apps.minio-apps:9000
      bucket: loki-chunks

promtail:
  daemonset: true  # All nodes

nodeSelector:
  cryptophys.io/tier: platform

ingress:
  host: loki.cryptophys.work
```

---

### Step 19: OpenTelemetry + Tempo
**Purpose:** Distributed tracing

**Configuration:**
```yaml
tempo:
  replicas: 3
  storage:
    trace:
      backend: s3
      s3:
        endpoint: minio-apps.minio-apps:9000
        bucket: tempo-traces

otelCollector:
  mode: daemonset  # All nodes

nodeSelector:
  cryptophys.io/tier: platform

ingress:
  host: tempo.cryptophys.work
```

---

### Step 20: Trivy Operator
**Purpose:** Continuous vulnerability scanning

**Configuration:**
```yaml
operator:
  replicas: 2

scanner:
  replicas: 3

reportStorage:
  type: s3
  s3:
    endpoint: minio-apps.minio-apps:9000
    bucket: trivy-reports

nodeSelector:
  cryptophys.io/tier: platform
```

---

### Step 21: Headlamp Dashboard
**Purpose:** Web UI for cluster management

**Configuration:**
```yaml
replicas: 2

nodeSelector:
  cryptophys.io/tier: platform

ingress:
  enabled: true
  host: dashboard.cryptophys.work
  
linkerd:
  inject: enabled
```

---

## VERIFICATION MATRIX

| Component | Replicas | Spread | Storage | Backup | SPOF? |
|-----------|----------|--------|---------|--------|-------|
| Cilium | DaemonSet | All nodes | - | - | No |
| API Server | 3 | 3 CP | - | etcd | No |
| Longhorn | DaemonSet | 5 nodes | Local+Net | Velero | No |
| PostgreSQL | 3 | 3 CP | Longhorn | WAL+Velero | No |
| SPIRE Server | 3 | 3 CP | PostgreSQL | Velero | No |
| SPIRE Agent | DaemonSet | All nodes | - | - | No |
| Linkerd CP | 3 | 3 CP | - | GitOps | No |
| Ingress NGINX | 3 | 3 CP | - | GitOps | No |
| MinIO-Velero | 4 | 3 CP + 1W | Longhorn | None | No |
| Velero | 1 | Any | MinIO+S3 | Config | No* |
| MinIO-Apps | 4 | All nodes | Longhorn | Velero | No |
| Redis | 1M+2R+3S | 3 CP | Longhorn | Velero | No |
| Gitea | 3 | 3 CP | PG+MinIO | Velero | No |
| Flux | 4 controllers | Any | Gitea | GitOps | No |
| Vault | 3 | 3 CP | Longhorn | Velero | No |
| Harbor | 3/component | 3 CP | PG+MinIO | Velero | No |
| Tekton | 3/component | 3 CP | - | GitOps | No |
| Kyverno | 3 | 3 CP | - | GitOps | No |
| Prometheus | 2+Thanos | 3 CP | MinIO | Velero | No |
| Loki | 3 | 3 CP | MinIO | Velero | No |

*Velero: Single pod acceptable, state in object storage

---

## INGRESS ROUTES

```
# Infrastructure
api.cryptophys.work → Kubernetes API (DNS round-robin)

# Observability
dashboard.cryptophys.work → Headlamp
prometheus.cryptophys.work → Prometheus
loki.cryptophys.work → Loki
tempo.cryptophys.work → Tempo
hubble.cryptophys.work → Hubble UI (Cilium)

# Platform Services
git.cryptophys.work → Gitea
harbor.cryptophys.work → Harbor
vault.cryptophys.work → Vault
tekton.cryptophys.work → Tekton Dashboard
argocd.cryptophys.work → ArgoCD

# Storage
minio.cryptophys.work → MinIO-Apps Console
velero-minio.cryptophys.work → MinIO-Velero Console

# Mesh
linkerd.cryptophys.work → Linkerd Viz
```

---

## DISASTER RECOVERY SCENARIOS

### Scenario 1: Single Node Failure
**Impact:** Zero downtime
**Recovery:** Automatic (Kubernetes reschedules)

### Scenario 2: Single CP Failure
**Impact:** Zero downtime (etcd quorum: 2/3)
**Recovery:** Automatic within 5 minutes

### Scenario 3: Storage Failure
**Impact:** Minimal (Longhorn 3x replication)
**Recovery:** Automatic rebuild

### Scenario 4: Complete Cluster Loss
**Impact:** RTO: 4 hours, RPO: 1 hour
**Recovery:**
1. Bootstrap new Talos cluster
2. Restore Velero from S3
3. Restore etcd snapshot
4. Restore PVCs from Longhorn backup

### Scenario 5: Data Corruption
**Impact:** RTO: 1 hour
**Recovery:**
1. Scale down affected service
2. Restore PVC from Velero
3. Restore database from WAL backup
4. Scale up service

---

## MAINTENANCE WINDOWS

**Zero-Downtime Operations:**
- Rolling updates: All stateless services
- PostgreSQL failover: <30s
- Longhorn volume migration: Transparent
- Ingress updates: Load-balanced

**Planned Downtime (if needed):**
- Talos OS upgrade: Sequential, 1 node at a time
- etcd maintenance: With quorum
- Major version upgrades: Blue-green deployment

---

## COST OPTIMIZATION

**Resource Allocation:**
- Total CP workloads: ~30GB RAM, ~15 CPU cores
- Total Worker capacity: Reserved for applications
- Storage: 1TB usable (3TB raw with 3x replication)

**Scaling Strategy:**
- Vertical: Increase node resources
- Horizontal: Add more workers for apps
- Storage: Add nodes for Longhorn capacity

---

## SUCCESS CRITERIA

- [ ] Zero SPOF in any layer
- [ ] All services 3+ replicas
- [ ] All data 3x replicated
- [ ] All state in persistent storage
- [ ] Backups to 2+ locations
- [ ] Full observability coverage
- [ ] Policy enforcement in audit
- [ ] Ingress for all services
- [ ] Linkerd mesh for all platform
- [ ] GitOps for all configuration

---

## EXECUTION TIMELINE

**Current Status:** Phase 0 Complete (Cilium, HA, Longhorn)

**Next Steps:** Phase 1 (PostgreSQL → SPIRE → Linkerd)

**Estimated Time:**
- Phase 1: 3 hours
- Phase 2: 2 hours
- Phase 3: 4 hours
- Phase 4: 3 hours
- Phase 5: 6 hours
- Phase 6: 2 hours
- Phase 7: 4 hours

**Total: ~24 hours of sequential deployment**

**Parallel Opportunities:**
- Phase 3: MinIO instances can deploy simultaneously
- Phase 5: Independent services can deploy in parallel
- Phase 7: Observability components can deploy in parallel

---

**END OF DEPLOYMENT SEQUENCE**
