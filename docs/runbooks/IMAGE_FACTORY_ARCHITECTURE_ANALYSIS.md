# Image-Factory Architecture Analysis & Recommendations

**Date:** 2026-02-14  
**Cluster:** cryptophys-genesis  
**Current State:** Image-factory pipeline in tekton-build namespace

---

## Current Architecture

### Namespace Structure
```
tekton-pipelines/           # Tekton operator & controllers
tekton-pipelines-resolvers/ # Tekton resolvers
tekton-build/               # User pipelines (image-factory, build tasks)
```

### Image-Factory Pipeline Location
- **Pipeline:** `tekton-build/image-factory`
- **ServiceAccount:** `tekton-build/image-factory`
- **Secrets:** `tekton-build/harbor-registry-cred`, `tekton-build/gitea-ci-credentials`
- **BuildKit:** Runs as **sidecar container** in each PipelineRun Pod (not DaemonSet)

### BuildKit Execution Model
**Current: Sidecar (buildctl-daemonless.sh)**
```yaml
steps:
  - name: build-and-push
    image: moby/buildkit:v0.12.5-rootless
    script: |
      buildctl-daemonless.sh build \
        --frontend dockerfile.v0 \
        --output type=image,push=true
```

**NOT using:** Persistent BuildKit DaemonSet/Deployment

---

## Question: Why No Dedicated Namespace for Image-Factory?

### Current Approach: Co-located in `tekton-build`
**Rationale:**
1. **Simplicity:** All Tekton user workloads in one namespace
2. **RBAC Efficiency:** Single ServiceAccount can access all build resources
3. **Resource Sharing:** Shared secrets, PVCs, ConfigMaps
4. **Tekton Convention:** Most Tekton deployments use a single "build" namespace

**Pros:**
- ✅ Easier secret management (one namespace for all CI/CD secrets)
- ✅ Simpler RBAC (no cross-namespace permissions needed)
- ✅ Lower operational overhead
- ✅ Follows Tekton community patterns

**Cons:**
- ❌ No isolation between different pipeline types
- ❌ Resource quotas apply to all pipelines collectively
- ❌ Security blast radius larger (one compromise affects all pipelines)
- ❌ Network policies harder to scope precisely

---

## Question: Why No Dedicated BuildKit Namespace?

### Current Approach: BuildKit as Sidecar (buildctl-daemonless.sh)
**Rationale:**
1. **Rootless Security:** Each build isolated in its own Pod
2. **No Shared State:** No cache sharing = simpler security model
3. **Auto-scaling:** BuildKit scales with PipelineRuns automatically
4. **Ephemeral:** No persistent infrastructure to maintain

**Pros:**
- ✅ **Maximum isolation:** Each build cannot access others
- ✅ **Zero persistent infrastructure:** No DaemonSet to maintain
- ✅ **Rootless by design:** Runs as user 1000, no privileges
- ✅ **Kyverno compliant:** Passes Pod Security Standards
- ✅ **Auto-cleanup:** BuildKit dies when PipelineRun completes

**Cons:**
- ❌ **No layer caching across builds:** Slower repeated builds
- ❌ **Higher resource usage:** Full BuildKit per build
- ❌ **Longer startup time:** ~10s overhead per build
- ❌ **Cannot use distributed BuildKit features**

### Alternative: Persistent BuildKit DaemonSet
**Would require:**
```
buildkit-system/
  ├── buildkitd DaemonSet (1 per node)
  ├── TLS certificates
  ├── Shared cache volumes
  └── NetworkPolicies
```

**Pros:**
- ✅ **Layer cache reuse:** 50-90% faster repeated builds
- ✅ **Lower per-build overhead:** No BuildKit startup
- ✅ **Distributed builds:** Cross-node cache sharing possible
- ✅ **Advanced features:** Multi-stage cache, export/import

**Cons:**
- ❌ **Persistent attack surface:** Always running
- ❌ **Complex RBAC:** Need cross-namespace access
- ❌ **Shared cache risks:** Cache poisoning attacks possible
- ❌ **Node affinity issues:** Must run on nodes with storage
- ❌ **Resource reservation:** Always consuming memory/CPU
- ❌ **Certificate management:** TLS for client auth

---

## Recommended Architecture (Current is CORRECT)

### ✅ **Keep Image-Factory in `tekton-build` Namespace**

**Reasoning:**
1. **Security Posture:** cryptophys uses rootless BuildKit sidecars = excellent isolation
2. **Operational Simplicity:** No additional namespace governance needed
3. **Compliance:** Already passes Kyverno Pod Security Standards
4. **Scale:** Cluster is 5 nodes, not 100+ (DaemonSet benefits minimal)
5. **GitOps:** Single namespace easier to manage via Flux

**When to reconsider:**
- Cluster grows to 50+ nodes
- Build frequency >100 builds/day (layer cache becomes critical)
- Need for specialized build node pools
- Regulatory requirement for build isolation

### ✅ **Keep BuildKit as Sidecar (buildctl-daemonless.sh)**

**Reasoning:**
1. **Zero Trust:** Each build is completely isolated
2. **Rootless:** Runs as UID 1000, no host access
3. **Ephemeral:** No persistent state to secure
4. **Compliance:** Meets Pod Security Restricted profile
5. **Maintainability:** No DaemonSet upgrade coordination

**When to reconsider:**
- Build times >5 minutes and layer cache would save 50%+
- Build frequency >20 builds/hour
- Multi-arch builds need distributed workers
- Network bandwidth to external registries becomes bottleneck

---

## Current Issues & Fixes

### Issue 1: Failed PipelineRun (image-factory-test-88jd5)
**Status:** Failed at clone task  
**Likely Cause:** Git credentials or network policy

**Fix:**
```bash
# Check clone task failure
kubectl logs -n tekton-build image-factory-test-88jd5-clone-pod

# Common issues:
# 1. Gitea not accessible (NetworkPolicy)
# 2. Git credentials invalid
# 3. Repository doesn't exist
```

### Issue 2: Harbor Push Path Not Configured
**Current:** Pipeline expects `harbor-registry-cred` secret  
**Need:** Verify Harbor credentials are correct

**Fix:**
```bash
# Verify Harbor secret exists and is valid
kubectl get secret -n tekton-build harbor-registry-cred -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d | jq .

# Test Harbor access from pipeline ServiceAccount
kubectl run test-harbor --rm -i --restart=Never \
  --image=curlimages/curl:latest \
  --serviceaccount=image-factory \
  -n tekton-build \
  -- curl -u admin:password https://registry.cryptophys.work/api/v2.0/health
```

### Issue 3: BuildKit Resource Limits Too High
**Current:** 4Gi memory, 2 CPU per build  
**Problem:** Cluster nodes have limited resources (control-plane only)

**Fix:**
```yaml
# Reduce BuildKit resources for control-plane scheduling
resources:
  requests:
    cpu: 200m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 2Gi
```

### Issue 4: No Persistent Workspace for Multi-Stage Builds
**Current:** ephemeral workspace, no caching  
**Problem:** Repeated builds of same image are slow

**Fix (Optional):**
```yaml
# Add PVC for workspace caching
workspaces:
  - name: src
    volumeClaimTemplate:
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: longhorn-single
        resources:
          requests:
            storage: 5Gi
```

---

## Alternative Architectures Considered

### Option A: Dedicated `image-factory` Namespace ❌
**Verdict:** REJECTED - Unnecessary complexity for 5-node cluster

**Would add:**
- Cross-namespace RBAC for tekton-build → image-factory
- Duplicate secret management (Harbor creds in 2 places)
- NetworkPolicy coordination between namespaces
- No significant security benefit (same node pool)

### Option B: BuildKit DaemonSet in `buildkit-system` ❌
**Verdict:** REJECTED - Security/complexity cost exceeds benefits

**Would add:**
- Persistent attack surface (always-on daemon)
- Node affinity constraints (control-plane + workers)
- TLS certificate management
- Cache invalidation logic
- ~20% build speed improvement (not worth tradeoffs)

### Option C: Kaniko instead of BuildKit ⚠️
**Verdict:** CONSIDERED - Simpler but less capable

**Pros:**
- No daemon needed (like current buildctl-daemonless)
- Simpler Dockerfile support
- Better Kubernetes integration

**Cons:**
- No BuildKit advanced features (secrets, ssh, caching)
- Slower multi-stage builds
- Less actively maintained than BuildKit

**Decision:** Stick with BuildKit (more future-proof)

### Option D: Cloud Build Service (Google/AWS/Azure) ❌
**Verdict:** REJECTED - Requires external dependency

**Against cryptophys principles:**
- No external dependencies for core infrastructure
- Data sovereignty (images stay internal)
- Cost (external build minutes expensive)
- Network egress (large images to/from cloud)

---

## Recommended Improvements (Minimal Changes)

### 1. Add Image-Factory Namespace Labels
```bash
kubectl label namespace tekton-build \
  cryptophys.io/workload-type=ci-cd \
  cryptophys.io/image-factory=enabled
```

### 2. Create Dedicated NetworkPolicy
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: image-factory-allow-build
  namespace: tekton-build
spec:
  podSelector:
    matchLabels:
      tekton.dev/pipeline: image-factory
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: registry
    ports: [{protocol: TCP, port: 443}]  # Harbor
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: gitea
    ports: [{protocol: TCP, port: 3000}]  # Gitea
  - to:  # DNS
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports: [{protocol: UDP, port: 53}]
  - to: [{namespaceSelector: {}}]  # Allow all for external registries
    ports: [{protocol: TCP, port: 443}]
```

### 3. Add ResourceQuota for Build Namespace
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: image-factory-quota
  namespace: tekton-build
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    persistentvolumeclaims: "10"
  scopeSelector:
    matchExpressions:
    - operator: In
      scopeName: PriorityClass
      values: [system-cluster-critical, system-node-critical]
```

### 4. Add Kyverno Policy Exception for BuildKit
```yaml
apiVersion: kyverno.io/v1
kind: PolicyException
metadata:
  name: image-factory-buildkit
  namespace: kyverno
spec:
  exceptions:
  - policyName: cp-security-hardening-v1
    ruleNames: [require-ro-rootfs]
  match:
    any:
    - resources:
        kinds: [Pod]
        namespaces: [tekton-build]
        selector:
          matchLabels:
            tekton.dev/pipeline: image-factory
```

### 5. Fix Harbor Push Path Test
```bash
#!/bin/bash
# /opt/cryptophys/test-image-factory-push.sh

# Create simple test Dockerfile
cat > /tmp/test-build/Dockerfile <<EOF
FROM alpine:3.19
RUN echo "Test image from image-factory pipeline" > /test.txt
CMD ["cat", "/test.txt"]
EOF

# Create PipelineRun
kubectl create -n tekton-build -f - <<YAML
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: image-factory-test-$(date +%s)
spec:
  pipelineRef:
    name: image-factory
  params:
  - name: git_url
    value: https://github.com/docker-library/hello-world.git
  - name: git_revision
    value: master
  - name: image
    value: registry.cryptophys.work/library/test:$(date +%Y%m%d-%H%M%S)
  workspaces:
  - name: src
    emptyDir: {}
YAML

# Monitor progress
kubectl logs -n tekton-build -f -l tekton.dev/pipelineRun=image-factory-test-*
```

---

## Conclusion

### Current Architecture is CORRECT ✅

**Why:**
1. **Security:** Rootless BuildKit sidecars provide excellent isolation
2. **Compliance:** Passes Kyverno Pod Security Standards
3. **Simplicity:** Single namespace easier to operate
4. **Scale-appropriate:** 5-node cluster doesn't need DaemonSet complexity
5. **Maintainability:** No persistent infrastructure to secure

**Next Steps:**
1. ✅ Keep image-factory in tekton-build namespace
2. ✅ Keep BuildKit as sidecar (buildctl-daemonless)
3. ⚠️ Fix failed PipelineRun (diagnose clone task)
4. ⚠️ Verify Harbor push credentials
5. ⚠️ Add NetworkPolicy for build egress
6. ⚠️ Test end-to-end pipeline with /opt/cryptophys/test-image-factory-push.sh

**When to Revisit:**
- Cluster scales to 50+ nodes
- Build frequency exceeds 100/day
- Need for specialized build nodes
- Regulatory compliance requires additional isolation

---

**Recommendation:** Focus on fixing the current pipeline issues (clone task failure, Harbor credentials) rather than restructuring namespaces. The current architecture is sound for cryptophys scale and security requirements.
