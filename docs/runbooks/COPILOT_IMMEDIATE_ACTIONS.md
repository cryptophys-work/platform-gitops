# Copilot Immediate Action Plan

## Priority 1: Fix Gitea Database (SQLite → PostgreSQL HA)

**Problem:** Gitea currently using SQLite instead of PostgreSQL HA

**Root Cause:** Config at `/data/gitea/conf/app.ini` is auto-generated on first run

**Solution:**
1. Delete Gitea PVCs (will reset to fresh state)
2. Pre-seed database config in PostgreSQL HA
3. Redeploy Gitea with proper environment variables pointing to PostgreSQL HA
4. Initialize via web UI with PostgreSQL connection

**Commands:**
```bash
# Stop Gitea
kubectl scale statefulset gitea -n platform-gitops --replicas=0

# Delete PVCs to reset
kubectl delete pvc -n platform-gitops -l app=gitea

# Create Gitea database in PostgreSQL HA
kubectl run psql-init --rm -it --image=postgres:16 -- \
  psql postgresql://postgres:PASSWORD@postgres-ha-rw.postgresql-system.svc/postgres \
  -c "CREATE DATABASE gitea; CREATE USER gitea WITH PASSWORD 'secure-pass'; GRANT ALL ON DATABASE gitea TO gitea;"

# Redeploy with PostgreSQL env vars
kubectl set env statefulset/gitea -n platform-gitops \
  GITEA__database__DB_TYPE=postgres \
  GITEA__database__HOST=postgres-ha-rw.postgresql-system.svc.cluster.local:5432 \
  GITEA__database__NAME=gitea \
  GITEA__database__USER=gitea \
  GITEA__database__PASSWD=secure-pass

# Scale back up
kubectl scale statefulset gitea -n platform-gitops --replicas=2
```

## Priority 2: Secure Flux Authentication

**Problem:** Git URLs contain credentials: `http://user:pass@gitea...`

**Security Risk:** Credentials exposed in Git manifests

**Solution:** Use SSH keys or HTTP Basic Auth via Secret reference

**Update GitRepository CRs:**
```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: platform-repo
  namespace: flux-system
spec:
  url: http://gitea-http.platform-gitops.svc:3000/cryptophys/platform-gitops.git
  secretRef:
    name: gitea-flux-auth  # Already exists, contains username/password
  interval: 1m
```

**No credentials in URL!**

## Priority 3: Deploy Platform Services via Flux

Once Gitea is stable:

1. Create service manifests in `platform-gitops` repo
2. Commit to Git
3. Flux auto-deploys

**Services to Deploy:**
- [ ] MinIO (S3 storage)
- [ ] Vault (Secrets management) 
- [ ] Harbor (Container registry)
- [ ] Cert-manager (TLS)
- [ ] Nginx Ingress (External access)

---

**Status:** Ready to execute
**ETA:** 30 minutes
