# Post-Remediation Validation Checklist
**Generated:** 2026-02-14 04:58 UTC

---

## Pre-Deployment Validation (Completed ✅)

### File Integrity
- ✅ 8 manifests modified successfully
- ✅ 7 backup files created in `/tmp/kyverno-patches/`
- ✅ All modified files contain `@sha256:` digests
- ✅ YAML syntax validated (Python yaml.safe_load successful)

### Image Availability
- ✅ All 11 image digests resolved from upstream registries
- ✅ No 404 or authentication errors during resolution
- ✅ Digests correspond to specified tag versions

### Infrastructure Changes
- ✅ `gitea-http` Service created (10.97.106.140:3000)
- ✅ 3 Flux GitRepository resources updated
- ✅ Service selector matches 3/3 Gitea pods

---

## Cluster Validation (Pending - Requires API Access ⏳)

### Step 1: Cluster Connectivity
```bash
kubectl cluster-info
kubectl get nodes
```
**Expected:** All nodes Ready, API server responsive

### Step 2: Gitea Service Validation
```bash
kubectl get svc -n gitea gitea-http
kubectl get endpoints -n gitea gitea-http
```
**Expected:** ClusterIP assigned, 3 endpoints listed

### Step 3: Flux GitRepository Status
```bash
flux get sources git -A
```
**Expected:** All 3 repos show READY=True

### Step 4: Dry-Run Validation
```bash
# SPIRE manifests
kubectl apply --dry-run=server -k repos/platform-gitops-live/platform/infrastructure/spire/

# Redpanda manifests
kubectl apply --dry-run=server -k repos/cryptophys-apps-gitops/apps/aladdin/overlays/prod/

# Headlamp manifest
kubectl apply --dry-run=server -f repos/cryptophys-apps-gitops/apps/dash/overlays/prod/deployment.yaml

# Tekton pipelines
kubectl apply --dry-run=server -f repos/cryptophys-apps-gitops/apps/tekton/base/build/image-factory-pipeline.yaml
```
**Expected:** No Kyverno admission denials, no validation errors

### Step 5: Kyverno PolicyReport
```bash
kubectl get policyreport -A
kubectl get clusterpolicyreport
```
**Expected:** Reduced violation count compared to KYVERNO_COMPLIANCE_REPORT.md

### Step 6: Image Pull Test
```bash
# Test one image from each registry
kubectl run test-busybox --image=busybox@sha256:b9598f8c98e24d0ad42c1742c32516772c3aa2151011ebaf639089bd18c605b8 --rm -it -- /bin/sh
kubectl run test-spire --image=ghcr.io/spiffe/spire-agent@sha256:1085124f6c71e904ec302df8ff47d7cce21992015b3252898ba9d71daebdc377 --rm -it -- /bin/sh
kubectl run test-redpanda --image=docker.redpanda.com/redpandadata/console@sha256:825ef1b5979f51d7d02eccc275250425c86fa3b4f28a013dbb1a2639bfa663d1 --rm -it -- /bin/sh
```
**Expected:** All images pull successfully

---

## Functional Validation (Post-Deployment)

### SPIRE Workloads
```bash
kubectl get pods -n spire
kubectl logs -n spire -l app=spire-agent --tail=50
kubectl logs -n spire -l app=spire-server --tail=50
```
**Expected:** Pods Running, no security context errors

### Redpanda Workloads
```bash
kubectl get pods -n aladdin
kubectl exec -n aladdin redpanda-0 -- rpk cluster info
```
**Expected:** StatefulSet healthy, cluster operational

### Headlamp Dashboard
```bash
kubectl get pods -n dash
kubectl port-forward -n dash svc/headlamp 8080:80
# Browse to http://localhost:8080
```
**Expected:** UI accessible, no image pull errors

### Tekton Pipelines
```bash
kubectl get pipelines -n tekton-pipelines
kubectl create -f test-pipelinerun.yaml  # Use existing test
kubectl get pipelineruns -n tekton-pipelines
```
**Expected:** Pipeline tasks use digest-based images

---

## Rollback Validation (If Issues Occur)

### Restore Original Manifests
```bash
cd /tmp/kyverno-patches
ls -lh *.orig

# Example restore:
cp spire-agent.yaml.orig /opt/cryptophys/repos/platform-gitops-live/platform/infrastructure/spire/agent.yaml
cp spire-server.yaml.orig /opt/cryptophys/repos/platform-gitops-live/platform/infrastructure/spire/server.yaml
# Repeat for all backed up files
```

### Revert Gitea Service
```bash
kubectl delete svc gitea-http -n gitea
kubectl patch gitrepository apps-repo -n flux-system --type=json -p '[{"op":"replace","path":"/spec/url","value":"http://platform-code-forge-gitea-http.gitea.svc.cluster.local:3000/cryptophys.adm/apps-gitops.git"}]'
# Repeat for platform-repo and ssot-core-repo
```

### Force Flux Re-sync
```bash
flux reconcile source git platform-repo
flux reconcile kustomization platform-infrastructure
```

---

## Security Review Checklist

### SPIRE Security Context Compatibility
- [ ] Verify `hostPID: true` still works with `runAsNonRoot: true`
- [ ] Check `hostNetwork: true` compatibility with seccompProfile
- [ ] Test SPIRE agent registration with new security contexts
- [ ] Validate socket permissions (/run/spire/sockets)

**Mitigation if fails:** Add Kyverno policy exclusion:
```yaml
spec:
  match:
    any:
    - resources:
        namespaces:
        - spire
```

### Resource Limit Impact
- [ ] Monitor SPIRE agent memory usage (alert if >200Mi)
- [ ] Monitor SPIRE server memory usage (alert if >200Mi)
- [ ] Check for OOMKilled events
- [ ] Adjust limits if legitimate usage exceeds defaults

### Registry Access
- [ ] Confirm all registries reachable from cluster
- [ ] Verify Harbor proxy cache config (if using)
- [ ] Check ImagePullSecrets in namespaces
- [ ] Test digest-based pull for private registries

---

## Documentation Updates Required

After successful validation:

1. Update `KYVERNO_COMPLIANCE_REPORT_FINAL.md` with actual compliance %
2. Add validation results to `KYVERNO_REMEDIATION_CHANGELOG.md`
3. Update `KYVERNO_COMPLIANCE_GUIDE.md` with lessons learned
4. Create runbook entry for future compliance sweeps
5. Document any policy exclusions added

---

## Sign-Off

### Pre-Deployment Sign-Off ✅
- [x] Manifests modified correctly
- [x] Backups created
- [x] Image digests verified
- [x] Documentation complete

**Signed:** cryptophys.adm @ 2026-02-14 04:58 UTC

### Post-Deployment Sign-Off ⏳
- [ ] Dry-run validation passed
- [ ] Workloads deployed successfully
- [ ] No regressions detected
- [ ] Compliance improvement confirmed

**Pending:** Cluster API connectivity restoration

---

**End of Checklist**
