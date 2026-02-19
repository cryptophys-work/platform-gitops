# Tekton CI/CD Infrastructure

Note: Tekton pipelines/tasks are now managed by ArgoCD from `apps-gitops`.
This folder is retained for historical reference only.

**Institutional-grade continuous integration and delivery platform with automatic image signing, SBOM generation, and supply chain security.**

## Architecture

### Components

- **Tekton Pipelines** (v0.56.x): Core pipeline execution engine
- **Tekton Chains** (v0.26.x): Automatic artifact signing with Cosign
- **Tekton Triggers**: Event-driven pipeline automation
- **Harbor Registry**: OCI-compliant artifact storage
- **Kyverno**: Image signature verification

### Security Features

✅ **Cryptographic Signing**
- Cosign key-pair signing
- SLSA v1 attestation format
- Rekor transparency log integration

✅ **SBOM Generation**
- Trivy-based vulnerability scanning
- CycloneDX SBOM format
- Attached as OCI artifacts

✅ **Supply Chain Security**
- Image digest enforcement
- Signature verification (Kyverno)
- Hermetic builds (isolated)

## Usage

### Build a Signed Image

```bash
# Apply pipeline for your language
kubectl apply -f pipelines/go/pipeline.yaml  # or python, nodejs, rust

# Create PipelineRun
cat <<YAML | kubectl apply -f -
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  name: my-app-build
  namespace: tekton-system
spec:
  pipelineRef:
    name: go-application-build
  params:
    - name: repo-url
      value: https://github.com/your-org/your-app.git
    - name: image-name
      value: library/my-app
    - name: image-tag
      value: v1.0.0
  workspaces:
    - name: shared-data
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 1Gi
YAML
```

### Verify Signed Image

```bash
# With Cosign
cosign verify --key cosign.pub \
  registry.cryptophys.work/library/my-app:v1.0.0

# Check Rekor log
./security/image-signing/rekor-verify.sh \
  registry.cryptophys.work/library/my-app@sha256:...
```

## Directory Structure

```
tekton/
├── chains/
│   └── chains-config.yaml          # Signing configuration
├── tasks/
│   ├── buildah-build-push-sbom.yaml
│   ├── upload-sbom-artifact.yaml
│   └── buildx-multiarch.yaml
├── pipelines/
│   ├── go/pipeline.yaml
│   ├── python/pipeline.yaml
│   ├── nodejs/pipeline.yaml
│   └── rust/pipeline.yaml
├── monitoring/
│   └── servicemonitors.yaml
├── rbac/
│   └── pipeline-rbac.yaml
├── quotas/
│   └── resource-quotas.yaml
└── README.md
```

## Monitoring

ServiceMonitors deployed for:
- Tekton Pipelines Controller (port 9090)
- Tekton Chains Controller (port 9090)
- Tekton Triggers Controller (port 9090)

**Grafana dashboards:** https://monitor.cryptophys.work

## Operations

### Common Tasks

**Check build status:**
```bash
kubectl get pipelineruns -n tekton-system
```

**View logs:**
```bash
tkn pipelinerun logs my-app-build -n tekton-system -f
```

**Restart Chains:**
```bash
kubectl rollout restart deployment tekton-chains-controller -n tekton-chains
```

**Check signatures:**
```bash
kubectl get taskrun <name> -o jsonpath='{.metadata.annotations}' | grep chains
```

## Troubleshooting

### Common Issues

**Issue:** Chains not signing builds
- Check: `kubectl logs -n tekton-chains -l app=tekton-chains-controller`
- Verify: `kubectl get secret signing-secrets -n tekton-chains`

**Issue:** Build fails with authentication error
- Check: `kubectl get secret harbor-registry-creds -n tekton-system`
- Verify: Harbor credentials are correct

**Issue:** Kyverno blocks unsigned image
- Expected behavior in production namespaces
- Sign image or add PolicyException for development

## References

- Tekton: https://tekton.dev
- Chains: https://tekton.dev/docs/chains/
- Cosign: https://docs.sigstore.dev/cosign/
- SLSA: https://slsa.dev
- Rekor: https://docs.sigstore.dev/rekor/

---
**Status:** ✅ Production Ready
**Last Updated:** 2026-02-18
**Cluster:** cryptophys-genesis
