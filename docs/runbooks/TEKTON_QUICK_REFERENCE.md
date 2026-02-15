# Tekton Image-Factory Quick Reference

## 🚀 Quick Start

```bash
# Run quickstart script
/opt/cryptophys/tekton-image-factory-quickstart.sh

# Or specify custom image/repo
/opt/cryptophys/tekton-image-factory-quickstart.sh \
  registry.cryptophys.work/myapp/backend:v2.0 \
  https://github.com/myorg/backend-service
```

## 📋 Common Commands

### Trigger Pipeline
```bash
kubectl create -f pipelinerun.yaml
```

### Monitor Execution
```bash
# Watch all pipelines
kubectl get pipelinerun -n tekton-build --watch

# Watch specific run
kubectl get pipelinerun <name> -n tekton-build -w

# View all logs
kubectl logs -n tekton-build -l tekton.dev/pipelineRun=<name> --all-containers -f

# View specific stage logs
kubectl logs -n tekton-build <name>-clone-pod -c step-clone
kubectl logs -n tekton-build <name>-buildkit-pod -c step-build-and-push
kubectl logs -n tekton-build <name>-trivy-pod -c step-scan
kubectl logs -n tekton-build <name>-cosign-pod -c step-sign
```

### Check Status
```bash
# List all runs
kubectl get pipelinerun -n tekton-build

# Get run details
kubectl describe pipelinerun <name> -n tekton-build

# Check task status
kubectl get taskrun -n tekton-build -l tekton.dev/pipelineRun=<name>
```

### Cleanup
```bash
# Delete specific run
kubectl delete pipelinerun <name> -n tekton-build

# Delete all completed runs (older than 1 day)
kubectl delete pipelinerun -n tekton-build \
  --field-selector status.conditions[0].status=True

# Delete failed runs
kubectl delete pipelinerun -n tekton-build \
  --field-selector status.conditions[0].status=False
```

## 🔑 Required Secrets

```bash
# Gitea credentials
kubectl get secret gitea-ci-credentials -n tekton-build

# Harbor registry
kubectl get secret harbor-registry-cred -n tekton-build

# Cosign signing key
kubectl get secret cosign-signing-key -n tekton-build
```

## 🛠️ Troubleshooting

### Clone Stage Failed
```bash
# Check Gitea connectivity
kubectl run curl-test --image=curlimages/curl --rm -i --restart=Never -n tekton-build -- \
  curl -sk http://platform-code-forge-gitea-http.gitea.svc.cluster.local:3000/api/v1/version

# Verify credentials
kubectl get secret gitea-ci-credentials -n tekton-build -o jsonpath='{.data.username}' | base64 -d
```

### Build Stage Failed
```bash
# Check Harbor connectivity
kubectl run curl-test --image=alpine --rm -i --restart=Never -n tekton-build -- \
  wget -O- http://registry-harbor-core.registry.svc.cluster.local/api/v2.0/systeminfo

# Test docker login
docker login registry.cryptophys.work
```

### Scan Stage Failed
```bash
# Check Trivy availability
kubectl get pods -n registry | grep trivy

# Manual scan
trivy image registry.cryptophys.work/library/myapp:v1
```

### Pod Stuck in Pending
```bash
# Check Longhorn nodes
kubectl get node.longhorn.io -n longhorn-system

# Ensure node affinity targets ready nodes (cerebrum/corpus)
```

## 📦 Example PipelineRun

### Build from GitHub
```yaml
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: build-myapp-
  namespace: tekton-build
spec:
  pipelineRef:
    name: image-factory
  params:
    - name: git_url
      value: "https://github.com/myorg/myapp"
    - name: git_revision
      value: "main"
    - name: context_dir
      value: "."
    - name: dockerfile
      value: "Dockerfile"
    - name: image
      value: "registry.cryptophys.work/apps/myapp:v1.0"
    - name: trivy_severity
      value: "HIGH,CRITICAL"
    - name: trivy_exit_code
      value: "1"  # Block on vulnerabilities
  workspaces:
    - name: src
      volumeClaimTemplate:
        spec:
          accessModes: [ReadWriteOnce]
          resources:
            requests:
              storage: 2Gi
          storageClassName: longhorn
  taskRunTemplate:
    serviceAccountName: image-factory
    podTemplate:
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: kubernetes.io/hostname
                    operator: In
                    values:
                      - cerebrum-157-173-120-200
                      - corpus-207-180-206-69
      securityContext:
        fsGroup: 65532
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
```

### Build from Gitea (Once Repos Ready)
```yaml
params:
  - name: git_url
    value: "http://platform-code-forge-gitea-http.gitea.svc.cluster.local:3000/cryptophys.adm/myapp"
  - name: image
    value: "registry.cryptophys.work/apps/myapp:latest"
```

## 🔗 Useful Links

- **Documentation:** `/opt/cryptophys/TEKTON_IMAGE_FACTORY_ACTIVATION.md`
- **Quickstart Script:** `/opt/cryptophys/tekton-image-factory-quickstart.sh`
- **Pipeline Manifests:** `/opt/cryptophys/image-factory-*.yaml`
- **Tekton Dashboard:** `kubectl port-forward -n tekton-pipelines svc/tekton-dashboard 9097:9097`

## ⚠️ Important Notes

1. **Node Affinity Required:** Always target cerebrum/corpus nodes (Longhorn ready)
2. **Image Pull Times:** First run takes 5-8min (BuildKit + Trivy images), subsequent runs faster
3. **Gitea Repos:** Currently using external repos; internal Gitea repos pending initialization
4. **Registry:** Images pushed to `registry.cryptophys.work` (Harbor)
5. **Signing:** Images automatically signed with Cosign

## 📊 Pipeline Stages

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  Clone   │───▶│  Build   │───▶│   Scan   │───▶│   Sign   │
│  (Git)   │    │(BuildKit)│    │ (Trivy)  │    │(Cosign)  │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
                                                       │
                                                       ▼
                                              ┌─────────────────┐
                                              │  Harbor Push    │
                                              │ (with signature)│
                                              └─────────────────┘
```

**Total Time:** ~2-3 minutes (after images cached)

---

**Last Updated:** 2026-02-14  
**Pipeline Version:** image-factory v1.0  
**Tekton Version:** v1.6.0
