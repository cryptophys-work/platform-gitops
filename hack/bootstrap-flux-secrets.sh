#!/usr/bin/env bash
# bootstrap-flux-secrets.sh
# Idempotent: creates Flux bootstrap secrets from local gh CLI credentials.

set -euo pipefail

NAMESPACE="${1:-flux-system}"

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI not found" >&2
  exit 1
fi

GITHUB_TOKEN=$(gh auth token) # gitleaks:allow
echo "==> Token: ${GITHUB_TOKEN:0:6}... (${#GITHUB_TOKEN} chars)"

echo "==> Creating/updating secret: github-repo-auth in ${NAMESPACE}..."
kubectl create secret generic github-repo-auth \
  --namespace "${NAMESPACE}" \
  --from-literal=username=git \
  --from-literal=password="${GITHUB_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl get secret github-repo-auth -n "${NAMESPACE}" \
  -o jsonpath='{.data.password}' | base64 -d | cut -c1-6 | xargs -I{} echo "    Verification: {}..."

echo "✅ Done. flux-system secrets are ready."

echo "⚠️  PRE-WAVE-20 REQUIREMENT — Store Cloudflare API token in Vault:"
echo "   vault kv put secret/cryptophys/cloudflare \\"
echo "     api_token=\$(cat /opt/cryptophys/secret/cloudflare/api_token)"
echo ""
echo "   Token file: /opt/cryptophys/secret/cloudflare/api_token (permissions: 600)"
echo "   (token needs Zone:DNS:Edit + Zone:Zone:Read for cryptophys.work)"
