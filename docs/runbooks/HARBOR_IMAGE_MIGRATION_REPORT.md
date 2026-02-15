# Harbor Image Migration Report

**Generated:** 2026-02-14 05:30 UTC  
**Migration Status:** PARTIAL - Interrupted by Harbor/Network Issues

## Executive Summary

- **Total Images Discovered:** 112 unique container images across the cluster
- **Migration Attempted:** 40 images before interruption
- **Successfully Migrated:** 2 images (5% of attempted)
- **Failed:** 37 images
- **Not Attempted:** 72 images (migration interrupted)
- **Already in Harbor:** 1 image (skipped)

## Migration Infrastructure

- **Harbor Version:** (detected via API)
- **Harbor URL:** registry.cryptophys.work
- **Internal Registry:** registry-harbor-registry.registry.svc.cluster.local:5000
- **Migration Tool:** Skopeo v1.17.0
- **Migration Pod:** registry.migration.worker (tekton-build namespace)
- **Authentication:** harbor_registry_user credentials

## Image Distribution by Source Registry

| Registry | Count | Purpose |
|----------|-------|---------|
| ghcr.io | 32 | GitHub Container Registry - Flux, Kyverno, Gitea, etc. |
| quay.io | 20 | Quay - ArgoCD, Cilium, cert-manager, Prometheus |
| docker.io | 14 | Docker Hub - Longhorn, Grafana, Bitnami |
| registry.k8s.io | 9 | Kubernetes Official - CoreDNS, kube-proxy, metrics-server |
| cr.l5d.io | 4 | Linkerd Service Mesh |
| public.ecr.aws | 2 | AWS ECR Public |
| Other | 31 | Various registries (HashiCorp, Redpanda, Curlimages, etc.) |

## Harbor Project Structure

Created/verified projects for organizing mirrored images:

- `library` - General purpose and short-name images
- `ghcr-mirror` - GitHub Container Registry mirrors
- `quay-mirror` - Quay.io mirrors  
- `dockerhub-mirror` - Docker Hub mirrors
- `k8s-mirror` - Kubernetes official images
- `linkerd-mirror` - Linkerd images
- `aws-mirror` - AWS ECR public images
- `redpanda-mirror` - Redpanda images
- `chainguard-mirror` - Chainguard images
- `gcr-mirror` - Google Container Registry mirrors

## Successful Migrations (2)

1. **busybox:1.36-test3** (docker.io/library)
   - Target: registry.cryptophys.work/library/busybox:1.36-test3
   - Multi-arch: 17 architectures copied

2. **ghcr.io/fluxcd/notification-controller:v1.2.4**
   - Target: registry.cryptophys.work/ghcr-mirror/fluxcd/notification-controller:v1.2.4
   - Multi-arch manifest list migrated successfully

## Failure Analysis

### Primary Failure Causes

1. **Harbor HTTP 500 Internal Server Error** (80% of failures)
   ```
   received unexpected HTTP status: 500 Internal Server Error
   checking whether a blob exists in registry-harbor-registry...
   ```
   - Likely causes: Harbor storage issues, database overload, or resource constraints
   - Affected: Longhorn images, busybox, node, kubectl

2. **Network Connection Denied** (15% of failures)
   ```
   dial tcp 10.107.138.114:5000: connect: operation not permitted
   ```
   - Likely cause: Cilium/Kyverno network policy blocking mid-migration
   - Occurred after ~40 images processed

3. **Manifest Not Found** (5% of failures)
   ```
   reading manifest in docker.io/bitnami/kubectl: manifest unknown
   ```
   - Source registry issue: Images don't exist or were deleted

### Images That Failed (Sample)

- All Longhorn CSI images (csi-attacher, csi-provisioner, csi-resizer, csi-snapshotter)
- Longhorn core images (engine, manager, instance-manager, share-manager)
- docker.io/library/busybox:1.28, :1.36
- docker.io/library/node:lts-alpine
- docker.io/library/alpine:3.19
- bitnami/kubectl:1.28.5, 1.30.10 (manifest not found)
- cgr.dev/chainguard/busybox (with digest)

## Root Cause Assessment

### Harbor Resource Constraints
Harbor registry service (registry-harbor-registry.registry.svc.cluster.local:5000) began returning HTTP 500 errors after processing ~10 images, suggesting:
- Insufficient resources (CPU/memory)
- Storage performance issues
- Database connection pool exhaustion
- Too many concurrent blob checks

### Network Policy Issues
After ~40 images, network connections to Harbor registry service were actively denied ("operation not permitted"), indicating:
- Kyverno policies may be rate-limiting or blocking repeated connections
- Cilium network policy may have connection tracking limits
- Pod security context preventing network access

### Migration Strategy Issues
- Attempting all 112 images in a single sequential run
- No retry mechanism for transient failures
- No batching or rate limiting
- Timeout set to 300s per image (may be too long for smaller images)

## Impact Assessment

### Current State
- **2 images successfully in Harbor** (out of 112 needed)
- **Most critical infrastructure images NOT migrated:**
  - Longhorn storage (0/14 images)
  - Cilium networking (0/8 images)  
  - Linkerd service mesh (0/4 images)
  - Kubernetes core (0/9 images)
  - ArgoCD GitOps (0/1 images)

### Workload Impact
- **ZERO disruption** - No workloads affected (no manifest updates attempted)
- All pods continue pulling from external registries
- Kyverno policy `cp-supplychain-registry-v1` still in Audit mode

### Harbor Utilization
- Minimal storage used (~2 images)
- Harbor operational but resource-constrained under load
- Trivy scanning initiated for migrated images

## Recommendations

### Immediate Actions (Critical)

1. **Increase Harbor Registry Resources**
   ```bash
   kubectl -n registry scale deployment registry-harbor-registry --replicas=0
   kubectl -n registry patch deployment registry-harbor-registry \
     --patch '{"spec":{"template":{"spec":{"containers":[{"name":"registry","resources":{"requests":{"memory":"1Gi","cpu":"500m"},"limits":{"memory":"4Gi","cpu":"2000m"}}}]}}}}'
   kubectl -n registry scale deployment registry-harbor-registry --replicas=1
   ```

2. **Review Network Policies**
   - Check Cilium connection tracking limits
   - Review Kyverno policies for rate limiting
   - Add explicit allow policy for tekton-build → registry namespace

3. **Batch Migration Approach**
   - Split into 10-image batches
   - Add delays between batches (30s cooldown)
   - Process critical images first (Longhorn, Cilium, K8s)

### Migration Script Improvements

1. **Add Retry Logic**
   - Retry failed images up to 3 times with exponential backoff
   - Separate transient failures (500 errors) from permanent (manifest not found)

2. **Optimize Skopeo Parameters**
   - Remove `--all` flag for single-arch images
   - Add `--preserve-digests` for deterministic copies
   - Use `--dest-compress` to reduce network load

3. **Implement Parallel Migration**
   - Run 3-5 concurrent skopeo processes
   - Use separate migration pods per batch
   - Aggregate results at the end

### Long-term Strategy

1. **Harbor Proxy Cache**
   - Configure Harbor proxy cache projects for each external registry
   - Let Harbor pull-through cache images on-demand
   - Reduces migration burden and keeps images fresh

2. **Automated Sync**
   - Implement continuous sync for new images
   - Use Harbor replication rules
   - Integrate with Flux/ArgoCD image update automation

3. **Kyverno Policy Enforcement**
   - Keep in Audit mode until 95%+ images migrated
   - Create exceptions for images that can't be mirrored
   - Enforce in stages (namespace-by-namespace)

## Critical Images for Next Migration Batch

**Priority 1 - Storage (Longhorn - 14 images)**
```
docker.io/longhornio/longhorn-manager:v1.11.0
docker.io/longhornio/longhorn-engine:v1.11.0
docker.io/longhornio/longhorn-instance-manager:v1.11.0
docker.io/longhornio/longhorn-ui:v1.11.0
docker.io/longhornio/longhorn-share-manager:v1.11.0
docker.io/longhornio/csi-*
```

**Priority 2 - Networking (Cilium - 8 images)**
```
quay.io/cilium/cilium:v1.18.7
quay.io/cilium/operator-generic:v1.18.7
quay.io/cilium/hubble-relay:v1.18.7
quay.io/cilium/hubble-ui:v0.13.3
quay.io/cilium/hubble-ui-backend:v0.13.3
```

**Priority 3 - GitOps (ArgoCD, Flux - 9 images)**
```
quay.io/argoproj/argocd:v3.3.0
ghcr.io/fluxcd/*-controller:*
```

**Priority 4 - Kubernetes Core (9 images)**
```
registry.k8s.io/coredns/coredns:v1.11.1
registry.k8s.io/ingress-nginx/controller:v1.14.1
registry.k8s.io/metrics-server/metrics-server:v0.8.0
```

## Files Generated

- `/opt/cryptophys/harbor-image-mapping.yaml` - YAML mapping of source → Harbor images (40 entries)
- `/tmp/harbor-migration.log` - Full migration log with skopeo output
- `/tmp/harbor-failed-images.txt` - List of failed images (37 entries)
- `/tmp/harbor-migration-stats.txt` - Summary statistics (empty due to early termination)

## Next Steps

1. **DO NOT** proceed with full migration until Harbor resource issues resolved
2. Investigate Harbor logs: `kubectl logs -n registry -l component=registry --tail=200`
3. Check Harbor database health: `kubectl logs -n registry registry-harbor-database-0`
4. Review Cilium/Kyverno network policies affecting registry namespace
5. Test batch migration with 5-10 critical images
6. Monitor Harbor metrics during migration

## Success Criteria for Next Attempt

- [ ] Harbor registry pod scaled with adequate resources (1Gi+ memory, 500m+ CPU)
- [ ] Network policies reviewed and updated
- [ ] Batch migration script tested with 5 images
- [ ] Harbor health check passes before starting
- [ ] Migration completes without HTTP 500 or connection errors
- [ ] At least 50 images successfully migrated
- [ ] Critical infrastructure images (Longhorn, Cilium) migrated first

## Conclusion

The initial migration attempt revealed significant infrastructure issues with Harbor's resource allocation and network connectivity. While only 2 images were successfully migrated, the process validated the migration approach and identified specific bottlenecks. Addressing Harbor resource constraints and implementing batched migrations with retry logic will enable successful completion of the full 112-image migration.

**Recommendation:** Pause migration, resolve Harbor resource issues, then proceed with critical images in small batches.

---

**Report generated by:** Copilot CLI  
**Migration pod:** registry.migration.worker (tekton-build)  
**Harbor:** registry.cryptophys.work (registry namespace)
