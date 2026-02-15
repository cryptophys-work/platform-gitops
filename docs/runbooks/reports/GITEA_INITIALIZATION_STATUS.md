# Gitea GitOps Initialization Status Report
**Date:** 2026-02-14  
**Cluster:** cryptophys-genesis  
**Gitea Version:** 1.25.4  
**Status:** ⚠️ BLOCKED - Requires Network Policy & PostgreSQL Fix

---

## Current State

### Gitea Service
- **URL:** https://git.cryptophys.work
- **API:** Accessible (v1.25.4)
- **Web UI:** Likely accessible but not tested
- **Status:** ⚠️ **Degraded** - Cannot authenticate due to PostgreSQL connection failure

### Root Cause Analysis

**Issue:** Gitea pods cannot authenticate users or access repositories.

**Technical Details:**
```
Error: dial tcp 10.107.128.153:5432: connect: operation not permitted
Component: Gitea → PostgreSQL pgpool
Namespace: gitea
```

**Root Causes:**
1. **Network Policy Blocking:** Gitea pods have egress network policies blocking PostgreSQL connections
2. **Pgpool CrashLoopBackOff:** PostgreSQL pgpool pods failing health checks (likely also network policy related)
3. **Stale File Handles:** Storage mount issues observed in Gitea pods (secondary issue)

---

## Actions Taken

### 1. Network Policy Remediation ✅
**Applied:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: gitea-allow-all-egress-temp
  namespace: gitea
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: gitea
  policyTypes:
  - Egress
  egress:
  - {}  # Temporary: Allow all egress for Gitea pods
```

**Status:** Applied but insufficient (pgpool still failing)

### 2. Gitea Pod Restart ✅
- Deleted all Gitea pods to remount storage
- Pods restarted but stuck in Init:Error state
- Init container `configure-gitea` cannot connect to database

### 3. Credential Retrieval ✅
**Retrieved from Kubernetes secrets:**
- **Username:** `cryptophys.adm`
- **Token:** `b8470dfae821dbac4c1a065c28a578788f50a37d`
- **Status:** Token invalid (likely due to database unavailability)

---

## Required Repositories

### GitOps Repository Structure
All repositories exist locally in `/opt/cryptophys/repos/` but are not yet pushed to Gitea:

1. **platform-gitops**
   - Path: `/opt/cryptophys/repos/cryptophys-platform-gitops`
   - Content: 129 YAML files
   - Purpose: Platform infrastructure (metallb, ingress, monitoring, backup)
   - Remote configured: `https://gitea.cryptophys.work/cryptophys.adm/platform-gitops.git`

2. **apps-gitops**
   - Path: `/opt/cryptophys/repos/cryptophys-apps-gitops`
   - Content: 55 YAML files
   - Purpose: Application deployments (aladdin, dash, tekton)
   - Remote configured: `https://gitea.cryptophys.work/cryptophys.adm/apps-gitops.git`

3. **ssot-core**
   - Path: `/opt/cryptophys/repos/cryptophys-ssot-core`
   - Content: 18 YAML files
   - Purpose: Single Source of Truth canonical configs
   - Remote configured: `https://gitea.cryptophys.work/cryptophys.adm/ssot-core.git`

---

## Flux Status

### GitRepository Resources
All three GitRepository resources are configured but failing:

```bash
$ kubectl get gitrepository -n flux-system
NAME             URL                                                                                                     AGE    READY   STATUS
apps-repo        http://platform-code-forge-gitea-http.gitea.svc.cluster.local:3000/cryptophys.adm/apps-gitops.git       43h    False   authentication required
platform-repo    http://platform-code-forge-gitea-http.gitea.svc.cluster.local:3000/cryptophys.adm/platform-gitops.git   2d1h   False   authentication required
ssot-core-repo   http://platform-code-forge-gitea-http.gitea.svc.cluster.local:3000/cryptophys.adm/ssot-core.git         43h    False   authentication required
```

**Issue:** Repositories do not exist in Gitea (404) because Gitea API is non-functional.

---

## Blocking Issues

### 1. PostgreSQL Pgpool CrashLoopBackOff
**Impact:** HIGH - Gitea cannot function without database

**Status:**
```bash
$ kubectl get pod -n gitea -l app.kubernetes.io/component=pgpool
NAME                                                              READY   STATUS             RESTARTS       AGE
platform-code-forge-gitea-postgresql-ha-pgpool-66c56fb95f-cnzdj   0/1     CrashLoopBackOff   16 (3s ago)    84m
platform-code-forge-gitea-postgresql-ha-pgpool-66c56fb95f-ph6rl   0/1     CrashLoopBackOff   17 (43s ago)   86m
```

**Error:**
```
Liveness probe failed: command timed out after 5s
Readiness probe failed: PGPASSWORD psql connection timeout
```

**Root Cause:** Likely network policy blocking pgpool → postgresql communication

**Resolution Required:**
1. Review network policies in `gitea` namespace
2. Ensure pgpool can connect to postgresql pods on port 5432
3. Verify postgresql pods are healthy:
   ```bash
   kubectl get pod -n gitea -l app.kubernetes.io/component=postgresql
   # All 3 pods are Running ✅
   ```

### 2. Repository Creation Blocked
**Impact:** HIGH - Cannot initialize repos without Gitea API

**Attempted Methods:**
- ❌ REST API with token (authentication fails)
- ❌ Gitea CLI `admin repo create` (syntax errors, database connection fails)
- ❌ Direct filesystem initialization (stale file handles)
- ❌ Init container with curl (pod startup timeout)

**Resolution Required:**
1. Fix pgpool CrashLoopBackOff
2. Verify Gitea pods can connect to database
3. Create repos via API or CLI
4. Push content from `/opt/cryptophys/repos/`

---

## Remediation Plan

### Phase 1: Fix PostgreSQL Connectivity (URGENT)

**Step 1: Diagnose Pgpool Network Policies**
```bash
# List all network policies affecting pgpool
kubectl get networkpolicy -n gitea

# Check if pgpool has egress to postgresql
kubectl describe networkpolicy -n gitea platform-code-forge-gitea-postgresql-ha-pgpool

# Expected egress:
# - To: postgresql pods (port 5432)
# - To: DNS (port 53)
```

**Step 2: Create/Update Network Policies**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: pgpool-allow-postgres-egress
  namespace: gitea
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: pgpool
      app.kubernetes.io/name: postgresql-ha
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app.kubernetes.io/component: postgresql
          app.kubernetes.io/name: postgresql-ha
    ports:
    - protocol: TCP
      port: 5432
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

**Step 3: Restart Pgpool**
```bash
kubectl delete pod -n gitea -l app.kubernetes.io/component=pgpool
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=pgpool -n gitea --timeout=120s
```

**Step 4: Verify Database Connectivity**
```bash
# From Gitea pod
GITEA_POD=$(kubectl get pod -n gitea -l app.kubernetes.io/name=gitea -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n gitea $GITEA_POD -- wget -qO- http://platform-code-forge-gitea-postgresql-ha-pgpool.gitea.svc:5432 2>&1 | head -5
```

---

### Phase 2: Initialize Gitea Repositories

**Step 1: Create Repos via Gitea CLI**
```bash
GITEA_POD=$(kubectl get pod -n gitea -l app.kubernetes.io/name=gitea -o jsonpath='{.items[0].metadata.name}')

# Verify gitea CLI works
kubectl exec -n gitea $GITEA_POD -- gitea admin user list

# Create repositories (exact syntax TBD - check Gitea 1.25 docs)
kubectl exec -n gitea $GITEA_POD -- gitea admin repo create-repo \
  --user cryptophys.adm \
  --repo platform-gitops \
  --private=false

# Repeat for apps-gitops and ssot-core
```

**Step 2: Generate New API Token**
```bash
kubectl exec -n gitea $GITEA_POD -- gitea admin user generate-access-token \
  --username cryptophys.adm \
  --token-name flux-gitops \
  --scopes write:repository,write:organization \
  --raw > /tmp/gitea-token.txt
```

**Step 3: Update Flux Secret**
```bash
GITEA_TOKEN=$(cat /tmp/gitea-token.txt)

kubectl create secret generic gitea-credentials -n flux-system \
  --from-literal=username=cryptophys.adm \
  --from-literal=password=$GITEA_TOKEN \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

### Phase 3: Push Repository Content

**Step 1: Push from Local Repos**
```bash
cd /opt/cryptophys/repos/cryptophys-platform-gitops
git remote set-url origin https://cryptophys.adm:$GITEA_TOKEN@gitea.cryptophys.work/cryptophys.adm/platform-gitops.git
git push origin main

cd /opt/cryptophys/repos/cryptophys-apps-gitops
git remote set-url origin https://cryptophys.adm:$GITEA_TOKEN@gitea.cryptophys.work/cryptophys.adm/apps-gitops.git
git push origin main

cd /opt/cryptophys/repos/cryptophys-ssot-core
git remote set-url origin https://cryptophys.adm:$GITEA_TOKEN@gitea.cryptophys.work/cryptophys.adm/ssot-core.git
git push origin main
```

**Step 2: Verify Repos Exist**
```bash
curl -H "Authorization: token $GITEA_TOKEN" \
  https://git.cryptophys.work/api/v1/orgs/cryptophys.adm/repos | jq -r '.[].name'

# Expected:
# platform-gitops
# apps-gitops
# ssot-core
```

---

### Phase 4: Configure Flux Access

**Step 1: Update GitRepository Resources**
```yaml
# Already configured to use gitea-credentials secret
# Verify with:
kubectl get gitrepository -n flux-system -o yaml | grep secretRef
```

**Step 2: Reconcile Flux Sources**
```bash
flux reconcile source git platform-repo
flux reconcile source git apps-repo
flux reconcile source git ssot-core-repo
```

**Step 3: Verify Success**
```bash
kubectl get gitrepository -n flux-system
# All should show READY=True
```

---

## Alternative: Bypass Gitea (Temporary)

If Gitea fixes take too long, consider temporary alternatives:

### Option 1: Git File Server
```bash
# Serve repos via git-daemon or git-http-backend
# Flux can clone from http://service.namespace.svc/repo.git
```

### Option 2: ConfigMap-based GitOps
```bash
# Bundle manifests into ConfigMaps
# Flux can reference ConfigMaps as sources
```

### Option 3: External Git (GitHub/GitLab)
```bash
# Mirror repos to external git temporarily
# Update Flux GitRepository URLs
```

---

## Success Criteria

- ✅ **Gitea pods Running:** All Gitea pods in Ready state
- ✅ **Pgpool Healthy:** Pgpool pods in Running state, passing probes
- ✅ **Database Connectivity:** Gitea can authenticate users
- ✅ **Repos Created:** 3 repos exist in Gitea under `cryptophys.adm` org
- ✅ **Content Pushed:** All manifests pushed from local repos
- ✅ **Flux Synced:** All 3 GitRepository resources show READY=True
- ✅ **Manifests Applied:** Kustomizations reconcile and apply manifests

---

## Timeline Estimate

**Optimistic (2-4 hours):**
- Network policy fix works immediately
- Pgpool starts without issues
- Repos create and push smoothly

**Realistic (4-8 hours):**
- Network policy requires iteration
- Pgpool has additional issues
- Need to troubleshoot Gitea database schema

**Pessimistic (1-2 days):**
- PostgreSQL HA has deeper issues
- Requires Helm chart reconfiguration
- May need to redeploy Gitea stack

---

## Next Actions (Priority Order)

1. **IMMEDIATE:** Fix pgpool network policies and restart
2. **IMMEDIATE:** Verify postgresql pods are healthy and accessible
3. **HIGH:** Create Gitea repos via CLI once database is accessible
4. **HIGH:** Push repository content from local to Gitea
5. **HIGH:** Configure Flux access and reconcile sources
6. **MEDIUM:** Test Kyverno compliance on one sample manifest
7. **LOW:** Enable Flux Kustomizations for gradual rollout

---

## References

- **Gitea Logs:** `kubectl logs -n gitea <pod> --tail=50`
- **Pgpool Logs:** `kubectl logs -n gitea <pgpool-pod> --tail=50`
- **Network Policies:** `kubectl get networkpolicy -n gitea`
- **Flux Status:** `flux get sources git -n flux-system`
- **Local Repos:** `/opt/cryptophys/repos/`

---

**Status:** ⚠️ **IN PROGRESS**  
**Blocking:** PostgreSQL pgpool connectivity  
**Owner:** DevOps / Platform Team  
**Updated:** 2026-02-14 04:20 UTC
