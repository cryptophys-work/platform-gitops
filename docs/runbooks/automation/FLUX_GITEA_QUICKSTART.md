# Flux CD + Gitea Quick Reference

**Cluster:** cryptophys-genesis  
**Status:** ✅ Operational  
**Date:** 2026-02-15

---

## 🚀 Quick Start

### Make a Change via GitOps

```bash
# 1. Port-forward to Gitea (from host with kubectl access)
kubectl port-forward -n platform-gitops svc/gitea-http 3000:3000

# 2. Access Gitea Web UI
# Open browser: http://localhost:3000
# Login: cryptophys-admin / cryptophys-admin-2026-secure

# 3. Navigate to repository
# cryptophys/platform-gitops or cryptophys/apps-gitops

# 4. Edit files via web UI or clone locally:
git clone http://localhost:3000/cryptophys/platform-gitops.git
cd platform-gitops

# 5. Make changes (example - add a ConfigMap)
cat > core/my-config.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-config
  namespace: default
data:
  key: value
EOF

# 6. Update kustomization
cat >> core/kustomization.yaml << EOF
  - my-config.yaml
EOF

# 7. Commit and push
git add .
git commit -m "Add my-config ConfigMap"
git push origin main

# 8. Wait 1-5 minutes for Flux to apply
# Or force reconciliation immediately:
flux reconcile source git platform-repo
flux reconcile kustomization platform-core

# 9. Verify
kubectl get configmap -n default my-config
```

---

## 📊 Check Status

```bash
# All Flux resources
kubectl get gitrepository,kustomization -n flux-system

# Detailed status
flux get sources git
flux get kustomizations

# View reconciliation history
kubectl describe kustomization -n flux-system platform-core

# Check Flux controller logs
kubectl logs -n flux-system -l app=kustomize-controller --tail=50
```

---

## 🔄 Force Reconciliation

```bash
# Don't wait for the interval - sync now
flux reconcile source git platform-repo
flux reconcile kustomization platform-core

# Full chain
flux reconcile source git platform-repo && \
  flux reconcile kustomization platform-core && \
  flux reconcile kustomization platform-services && \
  flux reconcile kustomization apps
```

---

## 🏢 Repository URLs

```
Platform Infrastructure:
http://gitea-http.platform-gitops.svc:3000/cryptophys/platform-gitops.git

Applications:
http://gitea-http.platform-gitops.svc:3000/cryptophys/apps-gitops.git
```

---

## 📁 Repository Structure

### platform-gitops
```
platform-gitops/
├── core/               # Base resources, CRDs, namespaces
│   ├── kustomization.yaml
│   └── *.yaml
└── services/           # Platform services (Harbor, Gitea, etc)
    ├── kustomization.yaml
    └── *.yaml
```

### apps-gitops
```
apps-gitops/
├── kustomization.yaml
└── */                  # Application manifests
```

---

## 🔐 Credentials

### Gitea Admin
- **Username:** `cryptophys-admin`
- **Password:** `cryptophys-admin-2026-secure`
- **Use for:** Web UI access, user management

### Flux Automation
- **Username:** `cryptophys-flux`
- **Password:** `flux-gitops-2026-secure-token`
- **Use for:** Automated Git operations (already configured)

> ⚠️ **Security Note:** Change these passwords in production!

---

## 🛠️ Common Operations

### Suspend Reconciliation (for maintenance)
```bash
flux suspend kustomization platform-core
# Make manual changes if needed
flux resume kustomization platform-core
```

### View Flux Logs
```bash
# Source controller (Git sync)
kubectl logs -n flux-system -l app=source-controller --tail=100

# Kustomize controller (Apply)
kubectl logs -n flux-system -l app=kustomize-controller --tail=100

# All Flux logs
kubectl logs -n flux-system -l app.kubernetes.io/part-of=flux --tail=50
```

### Check What Flux Manages
```bash
# Resources created by platform-core
kubectl get all -A -l kustomize.toolkit.fluxcd.io/name=platform-core

# Resources created by any Flux kustomization
kubectl get all -A -l kustomize.toolkit.fluxcd.io/namespace=flux-system
```

---

## 🐛 Troubleshooting

### GitRepository Not Syncing
```bash
# Check secret
kubectl get secret -n flux-system gitea-flux-auth -o yaml

# Test Gitea connectivity
kubectl exec -n platform-gitops gitea-0 -- \
  curl -u "cryptophys-flux:flux-gitops-2026-secure-token" \
  http://localhost:3000/api/v1/user

# Describe for error messages
kubectl describe gitrepository -n flux-system platform-repo
```

### Kustomization Not Applying
```bash
# Check dependency status
kubectl get kustomization -n flux-system

# View events
kubectl describe kustomization -n flux-system platform-core

# Check controller logs
kubectl logs -n flux-system -l app=kustomize-controller | grep -i error
```

### Resource Not Created
```bash
# Verify kustomization status
kubectl get kustomization -n flux-system platform-core -o yaml

# Check if resource is in Git
kubectl exec -n platform-gitops git-pusher -- \
  git -C /tmp/platform-gitops ls-files core/

# Manually test kustomize build (from repo checkout)
kustomize build core/
```

---

## 📞 Health Check Script

```bash
#!/bin/bash
# Save as: /usr/local/bin/flux-health-check

echo "=== Flux CD Health Check ==="
echo ""

echo "Controllers:"
kubectl get deploy -n flux-system -o wide

echo ""
echo "GitRepositories:"
kubectl get gitrepository -n flux-system

echo ""
echo "Kustomizations:"
kubectl get kustomization -n flux-system

echo ""
echo "Recent Events:"
kubectl get events -n flux-system --sort-by='.lastTimestamp' | tail -10

echo ""
echo "Gitea:"
kubectl get pods -n platform-gitops -l app=gitea
```

---

## 📚 Additional Resources

- **Full Documentation:** `/opt/cryptophys/FLUX_GITEA_AUTONOMOUS_INTEGRATION_COMPLETE.md`
- **Flux Docs:** https://fluxcd.io/docs/
- **Gitea API:** http://localhost:3000/api/swagger (when port-forwarded)

---

## ⚡ Emergency Commands

### Restart Flux Controllers
```bash
kubectl rollout restart deployment -n flux-system
```

### Restart Gitea
```bash
kubectl rollout restart statefulset -n platform-gitops gitea
```

### Delete Test ConfigMap
```bash
kubectl delete configmap -n flux-system flux-test-config
```

### Recreate Flux Secret
```bash
kubectl create secret generic gitea-flux-auth \
  -n flux-system \
  --from-literal=username=cryptophys-flux \
  --from-literal=password=flux-gitops-2026-secure-token \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

**Last Updated:** 2026-02-15  
**Maintained By:** Platform Team  
**Support:** Check logs and events first, then consult full documentation
