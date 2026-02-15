# Kyverno Compliance Developer Guide
**cryptophys Kubernetes Cluster**  
**Last Updated:** 2026-02-14

---

## Overview

This guide helps developers write Kubernetes manifests that comply with cryptophys Kyverno policies. All manifests must pass policy validation before merging to GitOps repositories.

---

## Quick Reference: Common Fixes

### ✅ Use Image Digests (Not Tags)

**❌ Bad:**
```yaml
containers:
- name: app
  image: nginx:1.21
```

**✅ Good:**
```yaml
containers:
- name: app
  image: nginx@sha256:a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2
  # Corresponds to nginx:1.21
```

**How to get digest:**
```bash
# Method 1: Docker
docker pull nginx:1.21
docker inspect --format='{{index .RepoDigests 0}}' nginx:1.21

# Method 2: Skopeo (no local pull)
skopeo inspect docker://nginx:1.21 | jq -r '.Digest'

# Method 3: Crane (lightweight)
crane digest nginx:1.21
```

---

### ✅ Use Approved Registries

**Approved registries:**
- `registry.cryptophys.work` (Harbor - internal)
- `ghcr.io` (GitHub Container Registry)
- `quay.io` (Red Hat Quay)
- `reg.kyverno.io` (Kyverno images)
- `docker.redpanda.com` (Redpanda)

**❌ Bad:**
```yaml
containers:
- name: app
  image: alpine:3.18  # docker.io implicit
```

**✅ Good:**
```yaml
containers:
- name: app
  image: registry.cryptophys.work/dockerhub-proxy/alpine@sha256:...
  # OR use Harbor proxy cache
```

**Harbor Proxy Cache Setup:**
1. Navigate to Harbor UI: https://registry.cryptophys.work
2. Create proxy cache project: `dockerhub-proxy`
3. Point to: `https://registry-1.docker.io`
4. Update manifest to use: `registry.cryptophys.work/dockerhub-proxy/<image>`

---

### ✅ Add Security Context (Pod & Container)

**❌ Bad:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      containers:
      - name: app
        image: myapp@sha256:...
```

**✅ Good:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      securityContext:  # Pod-level
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      
      containers:
      - name: app
        image: myapp@sha256:...
        securityContext:  # Container-level
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true  # if app supports it
          capabilities:
            drop:
            - ALL
            add:  # Only add if absolutely required
            - NET_BIND_SERVICE  # Example: binding to port 80
```

**Notes:**
- `runAsNonRoot: true` is **required** for restricted PSS
- `allowPrivilegeEscalation: false` prevents privilege escalation
- `capabilities.drop: [ALL]` drops all Linux capabilities
- Only add back capabilities if truly needed
- `readOnlyRootFilesystem: true` strongly recommended (use emptyDir volumes for writable paths)

---

### ✅ Add Resource Requests & Limits

**❌ Bad:**
```yaml
containers:
- name: app
  image: myapp@sha256:...
  # No resources defined
```

**✅ Good:**
```yaml
containers:
- name: app
  image: myapp@sha256:...
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "500m"
```

**Sizing Guidelines:**

| Workload Type | Memory Request | Memory Limit | CPU Request | CPU Limit |
|--------------|----------------|--------------|-------------|-----------|
| Small app | 64Mi | 256Mi | 50m | 200m |
| Medium app | 128Mi | 512Mi | 100m | 500m |
| Large app | 256Mi | 1Gi | 200m | 1000m |
| Database | 512Mi | 2Gi | 250m | 1000m |
| Cache (Redis) | 128Mi | 512Mi | 100m | 500m |

**Notes:**
- Always set requests for proper scheduling
- Limits prevent resource exhaustion
- Memory limit too low = OOMKilled
- CPU limit too low = throttling

---

## Complete Manifest Template

### Deployment (Production-Ready)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: production
  labels:
    app: myapp
    app.kubernetes.io/name: myapp
    app.kubernetes.io/version: "1.0.0"
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: myapp-stack
    cryptophys.io/managed-by: gitops
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
        app.kubernetes.io/name: myapp
        app.kubernetes.io/version: "1.0.0"
    spec:
      # Pod-level security context
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      
      # Service account (if needed)
      serviceAccountName: myapp
      automountServiceAccountToken: false  # disable if not needed
      
      # Init container (if needed)
      initContainers:
      - name: init-config
        image: registry.cryptophys.work/library/busybox@sha256:a1b2c3...
        command: ['sh', '-c', 'echo "Initializing..."']
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        resources:
          requests:
            memory: "32Mi"
            cpu: "50m"
          limits:
            memory: "64Mi"
            cpu: "100m"
      
      # Main container
      containers:
      - name: app
        image: registry.cryptophys.work/myapp/backend@sha256:a1b2c3d4e5f6...
        
        # Container-level security context
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        
        # Ports
        ports:
        - name: http
          containerPort: 8080
          protocol: TCP
        
        # Environment variables
        env:
        - name: LOG_LEVEL
          value: "info"
        - name: DATABASE_HOST
          value: postgres.database.svc.cluster.local
        
        # Secrets (via external-secrets or sealed-secrets)
        envFrom:
        - secretRef:
            name: myapp-secrets
        
        # Volume mounts
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: cache
          mountPath: /app/cache
        - name: config
          mountPath: /app/config
          readOnly: true
        
        # Probes
        livenessProbe:
          httpGet:
            path: /healthz
            port: http
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        
        readinessProbe:
          httpGet:
            path: /ready
            port: http
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        
        # Resources (REQUIRED)
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
      
      # Volumes
      volumes:
      - name: tmp
        emptyDir: {}
      - name: cache
        emptyDir: {}
      - name: config
        configMap:
          name: myapp-config
      
      # Node affinity (optional)
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app: myapp
              topologyKey: kubernetes.io/hostname
```

---

## Policy-Specific Guidance

### Image Digest Policy (`cp-supplychain-images-digest-v1`)

**Applies to namespaces:**
- `bridge`
- `cerebrum`
- `aether`
- `gitea`

**How to comply:**
1. Resolve tag to digest: `skopeo inspect docker://image:tag | jq -r '.Digest'`
2. Replace `image:tag` with `image@sha256:...`
3. Add comment with original tag for reference

**Example:**
```yaml
# Before
image: nginx:1.21-alpine

# After
image: nginx@sha256:a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2
# Source: nginx:1.21-alpine
```

---

### Registry Policy (`cp-supplychain-registry-v1`)

**Excluded namespaces:**
- `kube-system`
- `platform-gitops`
- `registry`

**For all other namespaces:**
- Images must come from approved registries (see list above)
- Use Harbor proxy cache for docker.io images

**Harbor Proxy Configuration:**
```bash
# 1. Create proxy project in Harbor UI
# 2. Update manifest:
# FROM: alpine:3.18
# TO:   registry.cryptophys.work/dockerhub-proxy/alpine@sha256:...

# 3. Test pull:
docker pull registry.cryptophys.work/dockerhub-proxy/alpine:3.18
```

---

### Security Hardening Policy (`cp-security-hardening-v1`)

**Required fields:**

**Pod-level:**
- `securityContext.runAsNonRoot: true`
- `securityContext.seccompProfile.type: RuntimeDefault`

**Container-level:**
- `securityContext.runAsNonRoot: true`
- `securityContext.allowPrivilegeEscalation: false`
- `securityContext.capabilities.drop: [ALL]`

**Optional but recommended:**
- `securityContext.readOnlyRootFilesystem: true`
- `securityContext.runAsUser: 1000` (explicit UID)

**Troubleshooting:**

**Issue:** App crashes with "Permission denied"
**Solution:** App may require writable filesystem. Use emptyDir:
```yaml
volumeMounts:
- name: tmp
  mountPath: /tmp
volumes:
- name: tmp
  emptyDir: {}
```

**Issue:** App needs specific capability (e.g., NET_BIND_SERVICE)
**Solution:** Add only required capability:
```yaml
securityContext:
  capabilities:
    drop:
    - ALL
    add:
    - NET_BIND_SERVICE
```

---

### Resource Limits Policy (`cp-resource-limits-v1`)

**Required for:**
- All Deployments
- All StatefulSets
- All DaemonSets

**Both requests AND limits must be set:**
```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"
```

**Best practices:**
- Start conservative, increase based on metrics
- Monitor with: `kubectl top pod -n <namespace>`
- Set `requests = limits` for guaranteed QoS (databases, critical apps)
- Set `requests < limits` for burstable QoS (web apps, workers)

---

## Validation & Testing

### Pre-commit Validation

```bash
# Install kyverno CLI
kubectl krew install kyverno

# Validate manifest against policies
kyverno apply /path/to/policies --resource /path/to/manifest.yaml

# Check for violations
echo $?  # 0 = pass, non-zero = fail
```

### CI/CD Pipeline Integration

**GitLab CI:**
```yaml
kyverno-check:
  stage: validate
  image: ghcr.io/kyverno/kyverno-cli:latest
  script:
    - kyverno apply policies/ --resource manifests/ --policy-report
    - |
      if jq -e '.results[] | select(.result == "fail")' policy-report.json; then
        echo "Kyverno policy violations detected"
        exit 1
      fi
```

**GitHub Actions:**
```yaml
- name: Kyverno Policy Check
  uses: kyverno/action-kyverno@v1
  with:
    policies: policies/
    resources: manifests/
    fail-on-violation: true
```

### Dry-Run in Cluster

```bash
# Apply with server-side dry-run
kubectl apply --dry-run=server -f manifest.yaml

# Check for policy violations in output
# Kyverno admission webhook will validate and reject if violations exist
```

### Policy Report Inspection

```bash
# List all policy reports
kubectl get policyreport -A

# View violations in namespace
kubectl describe policyreport -n <namespace>

# Get summary
kubectl get policyreport -A -o json | jq '.items[] | {namespace: .metadata.namespace, passed: (.results | map(select(.result == "pass")) | length), failed: (.results | map(select(.result == "fail")) | length)}'
```

---

## Common Mistakes & Solutions

### Mistake 1: Using `latest` tag
**Error:** Image digest policy violation
**Solution:** Never use `latest`. Pin to specific version digest.

### Mistake 2: Running as root
**Error:** `runAsNonRoot` policy violation
**Solution:** Set `runAsUser: 1000` or build image with non-root user

### Mistake 3: No resource limits
**Error:** Resource limits policy violation
**Solution:** Add requests and limits (see sizing guide)

### Mistake 4: Privileged containers
**Error:** Security hardening policy violation
**Solution:** Remove `privileged: true`, use capabilities instead

### Mistake 5: External registry without proxy
**Error:** Registry policy violation
**Solution:** Configure Harbor proxy cache or replicate to Harbor

---

## Exemptions & Exceptions

### Requesting an Exemption

If your workload **cannot** comply with a policy (e.g., requires privileged access), request an exemption:

1. **Document justification:**
   - Why is non-compliance required?
   - What is the security risk?
   - What mitigations are in place?

2. **Create exception annotation:**
```yaml
metadata:
  annotations:
    kyverno.io/exception: "cp-security-hardening-v1"
    kyverno.io/exception-reason: "Requires CAP_SYS_ADMIN for eBPF tracing"
    kyverno.io/exception-approved-by: "security-team"
    kyverno.io/exception-expires: "2026-06-01"
```

3. **Submit for approval:** via GitOps PR with security team review

### Temporary Exclusions

For development/testing, temporarily exclude a namespace:
```yaml
# Add to policy
spec:
  rules:
  - exclude:
      any:
      - resources:
          namespaces:
          - my-dev-namespace
```

---

## Resources & Tools

### Official Documentation
- **Kyverno:** https://kyverno.io/docs/
- **Pod Security Standards:** https://kubernetes.io/docs/concepts/security/pod-security-standards/
- **cryptophys SSOT:** `/opt/cryptophys/ssot/`

### Tooling
- **Kyverno CLI:** `kubectl krew install kyverno`
- **Skopeo:** Image inspection without Docker
- **Crane:** Lightweight image operations
- **yq:** YAML processor for bulk updates

### Scripts
- Image digest generator: `/opt/cryptophys/tools/generate-image-digests.sh`
- Bulk fixer: `/opt/cryptophys/tools/fix-kyverno-violations.sh`
- Pre-commit hook: `/opt/cryptophys/tools/pre-commit-kyverno-check.sh`

### Getting Help
- **Slack:** #gitops-support
- **Email:** security@cryptophys.work
- **Docs:** https://docs.cryptophys.work/kyverno

---

## Changelog

### 2026-02-14
- Initial guide created
- Added complete manifest templates
- Added validation section

---

**Maintained by:** cryptophys Security Team  
**Last Review:** 2026-02-14  
**Next Review:** 2026-03-14
