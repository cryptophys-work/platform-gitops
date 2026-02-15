# Harbor Proxy Cache Configuration - Phase 1 Status

**Date:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")  
**Objective:** Enable Harbor proxy cache for quay.io and docker.io  
**Status:** ⚠️ **BLOCKED** - Authentication issues preventing API configuration

---

## Summary

### ✅ Completed
1. **Harbor Infrastructure Recovery**
   - Fixed database and Redis connectivity issues (network policies resolved)
   - Restarted all Harbor pods successfully
   - All 7 Harbor components now healthy (core, database, redis, registry, portal, jobservice, trivy)
   
2. **Ingress Configuration**
   - Added missing `ingressClassName: nginx` to Harbor ingress
   - Ingress controller verified running (3 replicas in `ingress` namespace)

3. **Policy Compliance**
   - Confirmed Kyverno policies in Audit mode (not blocking)
   - Policy exception `harbor-emergency-bootstrap` covers all Harbor resources

### ❌ Blocked
1. **Admin Password Authentication**
   - Password from secret `HARBOR_ADMIN_PASSWORD` does not work
   - Multiple authentication attempts failed, causing admin account lockout
   - Database password hash format unclear (32 char hex, claims SHA256 but too short)
   
2. **HTTPS Ingress Access**
   - Error 526 via `https://registry.cryptophys.work`
   - Likely Cloudflare SSL/TLS configuration issue

### 🔄 Not Started
- Creating Quay.io proxy cache registry endpoint
- Creating Docker Hub proxy cache registry endpoint  
- Creating proxy cache projects
- Testing image pulls through Harbor
- Updating workload imagePullSecrets

---

## Technical Details

### Harbor Component Health
```bash
$ kubectl get pods -n registry
NAME                                          READY   STATUS    RESTARTS
registry-harbor-core-84d56fcd77-xtpld         1/1     Running   0
registry-harbor-database-0                    1/1     Running   0
registry-harbor-jobservice-7d96b86d4b-fxfcm   1/1     Running   4
registry-harbor-portal-79b854b465-ts54p       1/1     Running   0
registry-harbor-redis-0                       1/1     Running   0
registry-harbor-registry-6b47b457f9-g49w7     2/2     Running   0
registry-harbor-trivy-0                       1/1     Running   0
```

**Health Check (unauthenticated):**
```bash
$ kubectl exec -n registry <core-pod> -- curl -s http://localhost:8080/api/v2.0/health | jq '.status'
"healthy"
```

### Authentication Issue Details

**Password from Helm values:**
```
harborAdminPassword: "HarborAdmin!2026"
```

**Database password record:**
```sql
username | password                         | password_version | salt
admin    | 6c986b7dbac90ad0f7a8cd0c94568499 | sha256           | IjJFovy4xoZdE5LwFT08ugAFIMqvaZTg
```

**Problem:** Hash algorithm mismatch
- Column `password` is `VARCHAR(40)` - suggests MD5 or SHA-1  
- Column `password_version` says `sha256` but SHA256 is 64 chars
- Actual hash is 32 chars (MD5 length)
- None of the tested hash combinations match:
  - MD5(password + salt)
  - SHA1(password + salt)  
  - SHA256 truncated
  - Default password "Harbor12345"

**Attempted Solutions:**
1. ✗ Basic auth with `HarborAdmin!2026` from secret
2. ✗ Default password `Harbor12345`
3. ✗ Generated bcrypt hash (column too short)
4. ✗ Generated SHA256 hash (column too short)
5. ✗ Generated MD5 hash (doesn't match)
6. ✗ Generated SHA1 hash (doesn't match)
7. ✗ Session-based auth (CSRF token required)

### Ingress Configuration

**Current State:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: registry-harbor-ingress
  namespace: registry
spec:
  ingressClassName: nginx  # ← Added during troubleshooting
  rules:
  - host: registry.cryptophys.work
    http:
      paths:
      - path: /api/
        backend:
          service:
            name: registry-harbor-core
            port: 80
      - path: /v2/
        backend:
          service:
            name: registry-harbor-core
            port: 80
      - path: /
        backend:
          service:
            name: registry-harbor-portal
            port: 80
  tls:
  - hosts:
    - registry.cryptophys.work
    secretName: registry-harbor-ingress
```

**Issue:** HTTPS returns Error 526 (invalid SSL certificate)

---

## Next Steps (Prioritized)

### Option 1: Use Harbor CLI (Recommended)
```bash
# Install Harbor CLI if available
# Configure using CLI commands instead of API
```

### Option 2: Access Web UI
```bash
# Fix HTTPS access first
# Navigate to https://registry.cryptophys.work
# Complete initial setup / password reset via web interface
# Manually create proxy cache projects
```

### Option 3: Helm Upgrade with Password Reset
```bash
# Force password reinitialization
helm upgrade registry-harbor harbor/harbor \
  --namespace registry \
  --set harborAdminPassword="NewPassword2026!" \
  --set forcePassword=true  # if such option exists
```

### Option 4: Direct Database Password Reset
```bash
# Research Harbor's exact password hashing algorithm
# Generate correct hash format
# Update database with correct password
```

### Option 5: Reinstall Harbor
```bash
# Last resort: Delete and reinstall with known password
# Would lose existing configuration
```

---

## Required Proxy Cache Configuration

Once authentication is resolved, execute:

### 1. Create Quay.io Registry Endpoint
```json
POST /api/v2.0/registries
{
  "name": "quay-io",
  "type": "quay",
  "url": "https://quay.io",
  "insecure": false
}
```

### 2. Create Quay.io Proxy Cache Project
```json
POST /api/v2.0/projects
{
  "project_name": "quay-cache",
  "registry_id": <quay_registry_id>,
  "metadata": {
    "public": "true"
  }
}
```

### 3. Create Docker Hub Registry Endpoint
```json
POST /api/v2.0/registries
{
  "name": "dockerhub",
  "type": "docker-hub",
  "url": "https://hub.docker.com",
  "insecure": false
}
```

### 4. Create Docker Hub Proxy Cache Project
```json
POST /api/v2.0/projects
{
  "project_name": "dockerhub-cache",
  "registry_id": <dockerhub_registry_id>,
  "metadata": {
    "public": "true"
  }
}
```

### 5. Test Image Pulls
```bash
# Via Quay.io cache
docker pull registry.cryptophys.work/quay-cache/bitnami/postgresql:16

# Via Docker Hub cache
docker pull registry.cryptophys.work/dockerhub-cache/library/redis:latest
```

---

## Commands for Next Session

```bash
# Check Harbor core pod status
kubectl get pods -n registry -l component=core

# Test Harbor health (always works)
kubectl exec -n registry $(kubectl get pod -n registry -l component=core -o name | head -1) -- \
  curl -s http://localhost:8080/api/v2.0/health | jq '.'

# Check Helm values
kubectl get secret -n registry sh.helm.release.v1.registry-harbor.v1 \
  -o jsonpath='{.data.release}' | base64 -d | base64 -d | gunzip | \
  jq -r '.config' | grep -i password

# Access Harbor via port-forward (bypass ingress)
kubectl port-forward -n registry svc/registry-harbor-core 8443:443

# Then open browser to: https://localhost:8443
```

---

## Lessons Learned

1. **Network Policies** can block Harbor internal communication (database, Redis)
2. **Ingress requires explicit class** in this cluster setup  
3. **Kyverno policies** in Audit mode generate warnings but don't block
4. **Harbor password hashing** is non-standard and poorly documented
5. **Always verify credentials** before attempting configuration via API

---

## Files Generated
- `/opt/cryptophys/HARBOR_PROXY_CACHE_STATUS.md` (this file)
- `/tmp/harbor_proxy_cache_status_report.md` (detailed technical report)

