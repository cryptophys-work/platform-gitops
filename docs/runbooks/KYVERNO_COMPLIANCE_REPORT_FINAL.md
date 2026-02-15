# Kyverno Compliance Remediation Report
**Date:** 2026-02-14  
**Action:** Batch manifest remediation for cryptophys-genesis cluster

## Changes Summary

### 1. Image Digest Violations Fixed (11 images across 8 manifests)

#### SPIRE Infrastructure (platform-gitops-live)
- ✅ `busybox:1.36` → `busybox@sha256:b9598f...`
- ✅ `ghcr.io/spiffe/spire-agent:1.8.0` → `@sha256:1085124f...`
- ✅ `ghcr.io/spiffe/spire-server:1.8.0` → `@sha256:91d3572a...`

**Files:**
- `repos/platform-gitops-live/platform/infrastructure/spire/agent.yaml`
- `repos/platform-gitops-live/platform/infrastructure/spire/server.yaml`

#### Redpanda (apps-gitops)
- ✅ `docker.redpanda.com/redpandadata/console:v2.3.8` → `@sha256:825ef1b5...`
- ✅ `docker.redpanda.com/redpandadata/redpanda:v23.2.19` → `@sha256:7c82bfb6...`

**Files:**
- `repos/cryptophys-apps-gitops/apps/aladdin/overlays/prod/console.yaml`
- `repos/cryptophys-apps-gitops/apps/aladdin/overlays/prod/statefulset.yaml`

#### Headlamp Dashboard (apps-gitops)
- ✅ `ghcr.io/headlamp-k8s/headlamp:v0.40.0` → `@sha256:16c34eb5...`

**Files:**
- `repos/cryptophys-apps-gitops/apps/dash/overlays/prod/deployment.yaml`

#### Tekton Pipelines (apps-gitops)
- ✅ `alpine/git:2.45.2` → `alpine/git@sha256:16ad8e78...`
- ✅ `moby/buildkit:v0.12.5-rootless` → `@sha256:917dfee8...`
- ✅ `aquasec/trivy:0.57.1` → `@sha256:5c59e08f...`

**Files:**
- `repos/cryptophys-apps-gitops/apps/tekton/base/build/image-factory-pipeline.yaml`
- `repos/cryptophys-apps-gitops/apps/tekton/base/build/dockerfile-build-pipeline.yaml`

### 2. Security Context Violations Fixed (2 workloads)

**SPIRE manifests enhanced with:**
- Pod-level security context: `runAsNonRoot: true`, `seccompProfile`, `fsGroup`
- Container security contexts: `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`

**Files:**
- `repos/platform-gitops-live/platform/infrastructure/spire/agent.yaml`
- `repos/platform-gitops-live/platform/infrastructure/spire/server.yaml`

### 3. Resource Limits Added (2 workloads)

Added requests/limits to all SPIRE containers:
```yaml
resources:
  requests: {memory: "64Mi", cpu: "50m"}
  limits: {memory: "256Mi", cpu: "500m"}
```

## Gitea Repository Initialization

✅ **Repositories Verified:**
- `cryptophys.adm/platform-gitops` (initialized, not empty)
- `cryptophys.adm/apps-gitops` (initialized, not empty)
- `cryptophys.adm/ssot-core` (initialized, not empty)

✅ **Gitea Service Fixed:**
- Created `gitea-http` ClusterIP service (10.97.106.140:3000)
- Updated Flux GitRepository URLs from headless to ClusterIP service

✅ **Flux Integration:**
- Updated 3 GitRepository resources to use stable DNS name
- Reconciliation triggered (pending API server reconnection)

## Compliance Metrics

**Before Remediation:**
- 82% compliant (166/202 manifests)
- 36 image digest violations
- 6 security context violations
- 3 resource limit violations

**After Remediation:**
- ~88% compliant (estimated 178/202 manifests)
- 25 image digest violations remaining (30% reduction)
- 4 security context violations remaining (33% reduction)
- 1 resource limit violation remaining (67% reduction)

## Remaining Work

### High Priority
1. **Tekton base manifests** (15+ images still using tags)
   - tekton-pipeline.yaml contains upstream Tekton CRDs with tag-based images
   - **Recommendation:** Accept upstream as-is or use Harbor proxy cache

2. **Node.js base images** (2 violations)
   - `node:lts-alpine` in Headlamp deployment
   - **Recommendation:** Use specific Node version with digest

3. **Non-compliant registries** (29 violations - not fixed yet)
   - Images from `docker.io`, `k8s.gcr.io`, etc.
   - **Recommendation:** Configure Harbor proxy cache projects

### Low Priority
1. Review SPIRE security context compatibility with hostPID/hostNetwork
2. Tune resource limits based on actual usage
3. Add Pod Disruption Budgets to critical workloads

## Validation Status

✅ Manifest syntax validated (YAML parsing successful)  
⏳ Kyverno policy validation (pending cluster API access)  
⏳ Dry-run apply (pending cluster API access)

## Backups

All original manifests backed up to:
- `/tmp/kyverno-patches/*.orig`

## Next Steps

1. **Immediate:** Reconnect to cluster API and validate with `kubectl apply --dry-run=server`
2. **Short-term:** Configure Harbor proxy cache for non-approved registries
3. **Medium-term:** Set Kyverno policies to Enforce mode (currently Audit)
4. **Long-term:** Establish GitOps workflow for automatic compliance checks in CI

---
**Report Generated:** 2026-02-14 04:52 UTC  
**Operator:** cryptophys.adm  
**Tools Used:** skopeo, sed, Python (yaml parsing)
