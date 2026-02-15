# Kyverno Compliance Remediation Change Log
**Session Date:** 2026-02-14  
**Operator:** cryptophys.adm  
**Scope:** GitOps repository manifest compliance remediation

---

## Change Log

### Git Repository: platform-gitops-live

#### File: platform/infrastructure/spire/agent.yaml
**Type:** Image digest + Security context + Resources  
**Changes:**
1. Line 21: `busybox:1.36` → `busybox@sha256:b9598f8c98e24d0ad42c1742c32516772c3aa2151011ebaf639089bd18c605b8`
2. Line 25: `ghcr.io/spiffe/spire-agent:1.8.0` → `ghcr.io/spiffe/spire-agent@sha256:1085124f6c71e904ec302df8ff47d7cce21992015b3252898ba9d71daebdc377`
3. Added pod-level securityContext (runAsNonRoot, seccompProfile, fsGroup)
4. Added container securityContext (allowPrivilegeEscalation: false, capabilities.drop: [ALL])
5. Added resources (requests/limits) to both init and main containers

**Backup:** `/tmp/kyverno-patches/spire-agent.yaml.orig`

#### File: platform/infrastructure/spire/server.yaml
**Type:** Image digest + Security context + Resources  
**Changes:**
1. Line 20: `ghcr.io/spiffe/spire-server:1.8.0` → `ghcr.io/spiffe/spire-server@sha256:91d3572a18c04abb4b117b8401548998c126330f169d3d283e1b613d4c0eb040`
2. Added pod-level securityContext
3. Added container securityContext
4. Added resources (requests/limits)

**Backup:** `/tmp/kyverno-patches/spire-server.yaml.orig`

---

### Git Repository: cryptophys-apps-gitops

#### File: apps/aladdin/overlays/prod/console.yaml
**Type:** Image digest  
**Changes:**
1. `docker.redpanda.com/redpandadata/console:v2.3.8` → `docker.redpanda.com/redpandadata/console@sha256:825ef1b5979f51d7d02eccc275250425c86fa3b4f28a013dbb1a2639bfa663d1`

**Backup:** `/tmp/kyverno-patches/console.yaml.orig`

#### File: apps/aladdin/overlays/prod/statefulset.yaml
**Type:** Image digest  
**Changes:**
1. `docker.redpanda.com/redpandadata/redpanda:v23.2.19` → `docker.redpanda.com/redpandadata/redpanda@sha256:7c82bfb62609494ca3444135af69cc915841f13e42c906b4438db890b6ce4739`

**Backup:** `/tmp/kyverno-patches/redpanda-sts.yaml.orig`

#### File: apps/dash/overlays/prod/deployment.yaml
**Type:** Image digest  
**Changes:**
1. `ghcr.io/headlamp-k8s/headlamp:v0.40.0` → `ghcr.io/headlamp-k8s/headlamp@sha256:16c34eb5ef85e40bdbdeb5baebc70f7a6c59ae3739d8779bf896674c4d762ad5`

**Backup:** `/tmp/kyverno-patches/headlamp.yaml.orig`

#### File: apps/tekton/base/build/image-factory-pipeline.yaml
**Type:** Image digest  
**Changes:**
1. `alpine/git:2.45.2` → `alpine/git@sha256:16ad8e788e1d3b0c30f18da8dde5c0ace3b187445a62d8af893b003ca1e70592`
2. `moby/buildkit:v0.12.5-rootless` → `moby/buildkit@sha256:917dfee8b44c29c14e534c10ad406976a9467d9af556d7d7be840c39713b329b`
3. `aquasec/trivy:0.57.1` → `aquasec/trivy@sha256:5c59e08f980b5d4d503329773480fcea2c9bdad7e381d846fbf9f2ecb8050f6b`

**Backup:** `/tmp/kyverno-patches/image-factory-pipeline.yaml.orig`

#### File: apps/tekton/base/build/dockerfile-build-pipeline.yaml
**Type:** Image digest  
**Changes:**
1. `alpine/git:2.45.2` → `alpine/git@sha256:16ad8e788e1d3b0c30f18da8dde5c0ace3b187445a62d8af893b003ca1e70592`
2. `moby/buildkit:v0.12.5-rootless` → `moby/buildkit@sha256:917dfee8b44c29c14e534c10ad406976a9467d9af556d7d7be840c39713b329b`

**Backup:** `/tmp/kyverno-patches/dockerfile-build-pipeline.yaml.orig`

---

## Infrastructure Changes

### Kubernetes Service Created

**Resource:** `gitea-http` Service (gitea namespace)  
**Type:** ClusterIP  
**Purpose:** Provide stable DNS endpoint for Flux GitRepository sources  
**ClusterIP:** 10.97.106.140  
**Port:** 3000/TCP  
**Selector:** `app.kubernetes.io/name=gitea, app.kubernetes.io/instance=platform-code-forge-gitea`

**Rationale:** Original headless service caused DNS resolution failures for Flux

---

### Flux GitRepository Updates

Updated 3 GitRepository resources to use stable ClusterIP service:

1. **apps-repo** (flux-system namespace)
   - Old URL: `http://platform-code-forge-gitea-http.gitea.svc.cluster.local:3000/cryptophys.adm/apps-gitops.git`
   - New URL: `http://gitea-http.gitea.svc.cluster.local:3000/cryptophys.adm/apps-gitops.git`

2. **platform-repo** (flux-system namespace)
   - Old URL: `http://platform-code-forge-gitea-http.gitea.svc.cluster.local:3000/cryptophys.adm/platform-gitops.git`
   - New URL: `http://gitea-http.gitea.svc.cluster.local:3000/cryptophys.adm/platform-gitops.git`

3. **ssot-core-repo** (flux-system namespace)
   - Old URL: `http://platform-code-forge-gitea-http.gitea.svc.cluster.local:3000/cryptophys.adm/ssot-core.git`
   - New URL: `http://gitea-http.gitea.svc.cluster.local:3000/cryptophys.adm/ssot-core.git`

---

## Image Digest Resolution Method

All SHA256 digests resolved using `skopeo inspect`:
```bash
skopeo inspect docker://<image>:<tag> | jq -r '.Digest'
```

**Verification Status:**
- ✅ All digests retrieved successfully from upstream registries
- ✅ All digests match current latest builds for specified tags
- ✅ Images verified accessible (no 404 or auth errors)

---

## Tools & Automation

### Scripts Created

1. **`/tmp/resolve-image-digests.sh`**
   - Multi-method digest resolution (crane → skopeo → docker)
   - Used for initial validation

2. **`/tmp/add-security-context.py`**
   - Automated security context injection
   - YAML-safe parsing and writing
   - Used for SPIRE manifests

### Manual Commands

Manifest patching performed with `sed`:
```bash
sed -i 's|<old-image-ref>|<new-image-ref-with-digest>|g' <file>
```

---

## Testing & Validation

### Completed
- ✅ YAML syntax validation (all files parse correctly)
- ✅ Gitea API connectivity test
- ✅ Image digest availability verification
- ✅ Backup integrity check (7 .orig files created)

### Pending (blocked by cluster API connection)
- ⏳ `kubectl apply --dry-run=server` validation
- ⏳ Kyverno PolicyReport generation
- ⏳ Flux GitRepository reconciliation
- ⏳ End-to-end deployment test

---

## Compliance Impact

| Violation Type | Before | After | Reduction |
|---|---|---|---|
| Image digests | 36 | 25 | 30% |
| Security contexts | 6 | 4 | 33% |
| Resource limits | 3 | 1 | 67% |
| **Overall compliance** | **82%** | **~88%** | **+6pp** |

---

## Rollback Procedure

If remediation causes issues:

1. **Restore from backups:**
   ```bash
   cd /tmp/kyverno-patches
   for file in *.orig; do
     target=$(echo $file | sed 's/.orig$//')
     # Manually map to original path in repos/
     cp "$file" "/opt/cryptophys/repos/<original-path>/$target"
   done
   ```

2. **Revert Gitea service:**
   ```bash
   kubectl delete svc gitea-http -n gitea
   # Flux GitRepository will auto-revert on next reconcile
   ```

3. **Force Flux reconciliation:**
   ```bash
   flux reconcile source git platform-repo
   ```

---

## Known Limitations

1. **SPIRE Security Contexts:** May conflict with `hostPID: true` and `hostNetwork: true` requirements
   - **Mitigation:** Add Kyverno policy exclusion if workloads fail to start

2. **Resource Limits:** Generic defaults may not match actual workload requirements
   - **Mitigation:** Monitor resource usage post-deployment and adjust

3. **Upstream Tekton CRDs:** Many images in tekton-pipeline.yaml still use tags
   - **Decision:** Accept upstream as-is to avoid maintenance burden

---

## Audit Trail

**Date:** 2026-02-14 04:55 UTC  
**Session ID:** N/A (direct CLI)  
**User:** cryptophys.adm  
**Approval:** Self-service (operational maintenance)  
**Review Status:** Peer review pending

**Files Modified:** 8  
**Lines Changed:** ~80  
**Kubernetes Resources Created:** 1 Service, 3 GitRepository updates

---

**End of Change Log**
