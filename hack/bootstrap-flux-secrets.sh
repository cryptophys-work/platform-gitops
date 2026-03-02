#!/usr/bin/env bash
# bootstrap-flux-secrets.sh
# Idempotent: creates Flux bootstrap secrets from local gh CLI credentials.
# Run once after fresh cluster bootstrap, or to restore after disaster recovery.
# Safe to run multiple times — uses kubectl apply (not create).
#
# Prerequisites:
#   - gh CLI authenticated: gh auth status
#   - kubectl connected to cluster: kubectl cluster-info
#   - flux-system namespace exists: kubectl get ns flux-system
#
# Usage:
#   chmod +x hack/bootstrap-flux-secrets.sh
#   ./hack/bootstrap-flux-secrets.sh

set -euo pipefail

NAMESPACE="flux-system"

echo "==> Checking prerequisites..."
gh auth status --hostname github.com >/dev/null 2>&1 || { echo "❌ gh CLI not authenticated. Run: gh auth login"; exit 1; }
kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 || { echo "❌ Namespace ${NAMESPACE} not found. Run wave 2 first."; exit 1; }

GITHUB_USER=$(gh api user --jq '.login')
GITHUB_TOKEN=$(gh auth token)

echo "==> User: ${GITHUB_USER}"
echo "==> Token: ${GITHUB_TOKEN:0:6}... (${#GITHUB_TOKEN} chars)"

echo ""
echo "==> Creating/updating secret: github-repo-auth in ${NAMESPACE}..."
kubectl create secret generic github-repo-auth \
  --namespace="${NAMESPACE}" \
  --from-literal=username="${GITHUB_USER}" \
  --from-literal=password="${GITHUB_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "==> Verification:"
kubectl get secret github-repo-auth -n "${NAMESPACE}" \
  -o jsonpath='{.metadata.name} | type={.type} | keys={.data}' 2>/dev/null
echo ""

echo ""
echo "✅ Done. flux-system secrets are ready."
echo "   Next: unsuspend 02-scheduling and 05-sources"
