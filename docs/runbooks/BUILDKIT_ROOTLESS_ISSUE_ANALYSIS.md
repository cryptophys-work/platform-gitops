# Image-Factory Pipeline Fix Summary

**Date:** 2026-02-14 05:30 UTC  
**Issue:** Rootless BuildKit cannot execute in restricted Pod Security environment

---

## Root Cause Analysis

### Problem: BuildKit Fails with "operation not permitted"

**Error:**
```
/proc/sys/user/max_user_namespaces needs to be set to non-zero.
[rootlesskit:parent] error: failed to start the child: fork/exec /proc/self/exe: operation not permitted
```

**Root Causes:**
1. **User Namespaces Blocked:** `/proc/sys/user/max_user_namespaces = 0` on nodes (Talos default)
2. **Seccomp Profile:** RuntimeDefault seccomp blocks user namespace syscalls
3. **Pod Security Standards:** Restricted profile prevents rootless container runtimes

### Why This Happens

Rootless BuildKit (buildctl-daemonless.sh) requires:
- User namespaces (`CLONE_NEWUSER` syscall)
- Ability to create sub-user namespaces
- Access to `/proc/sys/user/max_user_namespaces`

Talos OS + Kyverno Pod Security Restricted profile blocks these by design for security.

---

## Architecture Decision Point

### Current State:
- ✅ Clone task works
- ❌ BuildKit task fails (rootless cannot start)
- ❌ Cannot proceed to Trivy/Cosign/Push

### Option 1: Enable User Namespaces on Talos (REJECTED)
**Would require:**
```yaml
# Talos machine config
kernel:
  modules:
    - name: user-namespace
sysctls:
  user.max_user_namespaces: "15076"
```

**Why REJECTED:**
- Requires cluster-wide Talos reconfiguration
- Security regression (user namespaces = escape vector)
- Talos deliberately disables for hardening
- Not aligned with cryptophys security posture

### Option 2: Relax Security Context for BuildKit (PARTIAL SOLUTION)
**Add Kyverno PolicyException:**
```yaml
apiVersion: kyverno.io/v1
kind: PolicyException
metadata:
  name: buildkit-user-namespaces
  namespace: kyverno
spec:
  exceptions:
  - policyName: cp-pss-restricted-v1
    ruleNames:
    - restricted-capabilities
    - restricted-proc-mount
  match:
    any:
    - resources:
        kinds: [Pod]
        namespaces: [tekton-build]
        selector:
          matchLabels:
            tekton.dev/pipelineTask: buildkit
```

**Why PARTIAL:**
- Still may not work if Talos kernel blocks user namespaces
- Requires testing on actual cluster
- Security exception for specific workload (acceptable)

### Option 3: Switch to Privileged BuildKit (NOT RECOMMENDED)
**Would require:**
```yaml
securityContext:
  privileged: true  # Full host access
```

**Why NOT RECOMMENDED:**
- Massive security regression
- Violates Pod Security Standards
- Gives container full node access
- Against cryptophys principles

### Option 4: Use Kaniko Instead (RECOMMENDED) ✅
**Kaniko = Rootless OCI image builder, designed for Kubernetes**

**Advantages:**
- ✅ No daemon, no user namespaces needed
- ✅ Runs as non-root user in restricted security context
- ✅ Passes Pod Security Standards out-of-the-box
- ✅ Designed for Kubernetes/CI environments
- ✅ Harbor/Docker registry compatible
- ✅ Multi-stage Dockerfile support

**Disadvantages:**
- ❌ Slower than BuildKit (no advanced caching)
- ❌ Some BuildKit features not supported (secrets mounts, ssh)
- ❌ Less actively maintained than BuildKit

**Implementation:**
```yaml
steps:
- name: build-and-push
  image: gcr.io/kaniko-project/executor:v1.23.2
  script: |
    #!/bin/sh
    /kaniko/executor \
      --context=$(workspaces.src.path)/$(params.context_dir) \
      --dockerfile=$(params.dockerfile) \
      --destination=$(params.image) \
      --cache=true \
      --cache-repo=registry.cryptophys.work/cache \
      --skip-tls-verify=false \
      --verbosity=info
  securityContext:
    runAsUser: 1000
    runAsNonRoot: true
    allowPrivilegeEscalation: false
    capabilities:
      drop: ["ALL"]
    seccompProfile:
      type: RuntimeDefault
```

### Option 5: Use BuildKit with Privileged Security Context + Pod Identity (COMPROMISE)
**Minimal privilege elevation:**
```yaml
securityContext:
  runAsUser: 0  # Must run as root
  runAsNonRoot: false
  allowPrivilegeEscalation: true  # Required for buildkitd
  capabilities:
    add: ["SETUID", "SETGID"]  # Minimum for user namespaces
  seccompProfile:
    type: Unconfined  # Required for user namespace syscalls
```

**With Kyverno Exception:**
```yaml
apiVersion: kyverno.io/v1
kind: PolicyException
metadata:
  name: buildkit-elevated-privileges
spec:
  exceptions:
  - policyName: cp-security-hardening-v1
    ruleNames: [require-run-as-nonroot, require-drop-all-caps]
  - policyName: cp-pss-restricted-v1
    ruleNames: [restricted-capabilities, restricted-seccomp]
  match:
    any:
    - resources:
        kinds: [Pod]
        namespaces: [tekton-build]
        selector:
          matchLabels:
            app: buildkit
            cryptophys.io/workload-type: image-factory
```

---

## Recommended Solution: Migrate to Kaniko

### Justification:
1. **Security First:** No privilege elevation needed
2. **Kubernetes Native:** Designed for restricted environments
3. **Proven:** Used by Google Cloud Build, GitLab CI
4. **Compliant:** Passes all Kyverno policies
5. **Sufficient:** Meets cryptophys build requirements (simple Dockerfiles)

### Implementation Plan:
1. Create new pipeline task: `kaniko-build`
2. Replace BuildKit step with Kaniko executor
3. Test with same hello-world example
4. Update documentation
5. Keep BuildKit task as fallback (commented out)

### Migration Script:
See `/opt/cryptophys/migrate-to-kaniko.sh`

---

## Why Namespace Separation Still Not Needed

Even with this issue, dedicated namespace for image-factory is **not** the solution:

**Namespace wouldn't solve:**
- ❌ User namespace syscall blocks (kernel-level)
- ❌ Seccomp profile restrictions (applied per-pod)
- ❌ Pod Security Standards (namespace-scoped, same restrictions)

**Namespace would add:**
- ❌ Cross-namespace RBAC complexity
- ❌ Duplicate secret management
- ❌ NetworkPolicy coordination overhead

**Correct fix:** Change image builder technology (Kaniko), not namespace architecture.

---

## Next Steps

1. **Immediate:** Implement Kaniko migration (1-2 hours)
2. **Testing:** Run end-to-end pipeline with Kaniko
3. **Documentation:** Update TEKTON_QUICK_REFERENCE.md
4. **Validation:** Push 5 test images to Harbor
5. **Production:** Update all CI/CD pipelines to use Kaniko task

**Files to Create:**
- `/opt/cryptophys/migrate-to-kaniko.sh` - Migration script
- `/opt/cryptophys/kaniko-pipeline.yaml` - New pipeline definition
- `/opt/cryptophys/test-kaniko-build.sh` - Test script

---

**Conclusion:** Image-Factory architecture (single namespace, sidecar pattern) is correct. Issue is BuildKit incompatibility with Talos security model. Solution is Kaniko, not architectural change.
