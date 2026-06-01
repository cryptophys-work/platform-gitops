#!/usr/bin/env bash
# =============================================================================
# emergency-cert-renew.sh — manual Let's Encrypt wildcard cert renewal
# =============================================================================
# Use this when:
#   - cert-manager fails to auto-renew (API token expired, controller broken, etc)
#   - The wildcard cert is expiring within 24h and Flux is broken
#   - The 12 ESO-synced platform-wildcard-tls secrets are stale
#
# Requires:
#   - kubectl context to the target cluster
#   - VAULT_TOKEN with write policy on secret/data/*
#   - Cloudflare API token with Zone:DNS:Edit on cryptophys.work (in Vault)
#   - jc (https://github.com/kellyjonbrazil/jc) for JSON parsing
#   - openssl, base64, htpasswd
#
# Usage:
#   export VAULT_TOKEN=hvs.xxxxx
#   ./emergency-cert-renew.sh
#
# What it does:
#   1. Verifies prerequisites
#   2. Reads current cert from K8s
#   3. Triggers cert-manager to issue a new cert
#   4. Polls the cert-manager Order until valid
#   5. Extracts the issued cert + key
#   6. Writes the new cert to ALL platform-wildcard-tls secrets (12 namespaces)
#   7. Writes the new cert to apps-gateway/cryptophys-wildcard-cert
#   8. Writes the new cert to Vault secret/platform/tls/cryptophys-wildcard
#   9. Verifies the live HTTPS endpoint serves the new cert
# =============================================================================
set -euo pipefail

KUBECTL="kubectl --context=admin@cryptophys-genesis-1"
CERT_NAME="cryptophys-wildcard"
CERT_NS="cert-manager"
ISSUER="letsencrypt-prod"
SECRET_NAME="platform-wildcard-tls"
VAULT_PATH="secret/data/platform/tls/cryptophys-wildcard"
CF_VAULT_PATH="secret/cryptophys/cloudflare"
CF_PROP="api_token"
CF_ZONE_ID="e0454fafc33b614d3a22023c8e2d6e22"

# Namespaces that need the cert synced
TARGET_NAMESPACES=(
  apps-system
  cert-manager
  cqls-compute
  gitops-system
  ingress-system
  kube-system
  kyverno-system
  longhorn-system
  minio-system
  observability-system
  registry-system
  vault-system
)
TARGET_SECRETS=(
  "platform-wildcard-tls"      # 12 namespaces
  "cryptophys-wildcard-cert"   # apps-gateway
)

log() { printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
die() { log "FATAL: $*" >&2; exit 1; }

# -------------------------------------------------------------------- step 1
log "Step 1/9: Verifying prerequisites"
[ -n "${VAULT_TOKEN:-}" ] || die "VAULT_TOKEN env var required"
$KUBECTL get ns $CERT_NS >/dev/null || die "Cannot reach cluster"
log "  ✓ kubectl OK, VAULT_TOKEN present"

# Get the Cloudflare token from Vault if not in env
CF_TOKEN="${CLOUDFLARE_API_TOKEN:-}"
if [ -z "$CF_TOKEN" ]; then
  log "  Reading Cloudflare API token from Vault path $CF_VAULT_PATH/$CF_PROP"
  CF_TOKEN=$(kubectl --context=admin@cryptophys-genesis-1 -n vault-system exec vault-0 -- \
    sh -c "wget -qO- --header='X-Vault-Token: $VAULT_TOKEN' \
      http://127.0.0.1:8200/v1/$CF_VAULT_PATH" | \
    python3 -c "import json,sys,base64; d=json.load(sys.stdin); print(d['data']['data']['$CF_PROP'])" 2>/dev/null)
  [ -n "$CF_TOKEN" ] || die "Cannot read Cloudflare token from Vault"
fi
log "  ✓ Cloudflare token: ${CF_TOKEN:0:10}..."

# -------------------------------------------------------------------- step 2
log "Step 2/9: Reading current cert state"
CURRENT_CERT=$($KUBECTL -n $CERT_NS get secret $SECRET_NAME -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d)
CURRENT_EXP=$(echo "$CURRENT_CERT" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
CURRENT_NOTBEFORE=$(echo "$CURRENT_CERT" | openssl x509 -noout -startdate 2>/dev/null | cut -d= -f2)
log "  Current cert: notBefore=$CURRENT_NOTBEFORE, notAfter=$CURRENT_EXP"

# -------------------------------------------------------------------- step 3
log "Step 3/9: Forcing fresh cert issuance"
$KUBECTL -n $CERT_NS annotate certificate $CERT_NAME "force-renew-$(date +%s)" --overwrite 2>&1 | head -1
# Patch the spec to short duration to force immediate renewal
$KUBECTL -n $CERT_NS patch certificate $CERT_NAME --type=merge \
  -p '{"spec":{"duration":"240h","renewBefore":"239h"}}' 2>&1 | head -1
# Delete the secret to force a fresh issuance (cert-manager will detect missing secret)
$KUBECTL -n $CERT_NS delete secret $SECRET_NAME --wait=false 2>&1 | head -1
log "  ✓ Certificate annotated, secret deletion triggered"

# -------------------------------------------------------------------- step 4
log "Step 4/9: Polling for new order to become valid (max 5 min)"
SECONDS_WAITED=0
while [ $SECONDS_WAITED -lt 300 ]; do
  ORDER_VALID=$($KUBECTL -n $CERT_NS get order -o json 2>/dev/null | \
    python3 -c "
import json, sys
d = json.load(sys.stdin)
for item in d.get('items', []):
    if item.get('status', {}).get('state') == 'valid':
        print('YES')
        sys.exit(0)
print('NO')
" 2>/dev/null)
  if [ "$ORDER_VALID" = "YES" ]; then
    log "  ✓ Order is valid"
    break
  fi
  sleep 5
  SECONDS_WAITED=$((SECONDS_WAITED + 5))
  printf "."
done
[ "$ORDER_VALID" = "YES" ] || die "Order did not become valid within 5 min"

# -------------------------------------------------------------------- step 5
log "Step 5/9: Extracting issued cert from order"
ORDER_NAME=$($KUBECTL -n $CERT_NS get order -o json | \
  python3 -c "import json,sys; d=json.load(sys.stdin); [print(item['metadata']['name']) for item in d.get('items',[]) if item.get('status',{}).get('state')=='valid']" | head -1)
[ -n "$ORDER_NAME" ] || die "No valid order found"
log "  Using order: $ORDER_NAME"

# Find the private key secret created alongside
PRIV_KEY_SECRET=$($KUBECTL -n $CERT_NS get certificate $CERT_NAME -o jsonpath='{.status.nextPrivateKeySecretName}')
[ -n "$PRIV_KEY_SECRET" ] || die "No nextPrivateKeySecretName on cert"
log "  Using key secret: $PRIV_KEY_SECRET"

NEW_CRT=$($KUBECTL -n $CERT_NS get order $ORDER_NAME -o jsonpath='{.status.certificate}' | base64 -d)
NEW_KEY=$($KUBECTL -n $CERT_NS get secret $PRIV_KEY_SECRET -o jsonpath='{.data.tls\.key}' | base64 -d)

NEW_NOTBEFORE=$(echo "$NEW_CRT" | openssl x509 -noout -startdate | cut -d= -f2)
NEW_EXP=$(echo "$NEW_CRT" | openssl x509 -noout -enddate | cut -d= -f2)
log "  New cert: notBefore=$NEW_NOTBEFORE, notAfter=$NEW_EXP"

# Verify key matches cert
NEW_CRT_PUB=$(echo "$NEW_CRT" | openssl x509 -noout -pubkey)
NEW_KEY_PUB=$(echo "$NEW_KEY" | openssl rsa -pubout 2>/dev/null | grep -v "^writing")
[ "$NEW_CRT_PUB" = "$NEW_KEY_PUB" ] || die "Cert and key do NOT match!"
log "  ✓ Key matches cert"

# -------------------------------------------------------------------- step 6
log "Step 6/9: Patching cert in all ${#TARGET_NAMESPACES[@]} namespaces"
CERT_B64=$(echo "$NEW_CRT" | base64 -w0)
KEY_B64=$(echo "$NEW_KEY" | base64 -w0)
PATCH_JSON="{\"data\":{\"tls.crt\":\"$CERT_B64\",\"tls.key\":\"$KEY_B64\"}}"
for ns in "${TARGET_NAMESPACES[@]}"; do
  log "  Patching $ns/$SECRET_NAME"
  $KUBECTL --request-timeout=180s -n $ns patch secret $SECRET_NAME --type=merge -p "$PATCH_JSON" 2>&1 | head -1
done

# -------------------------------------------------------------------- step 7
log "Step 7/9: Patching apps-gateway/cryptophys-wildcard-cert"
$KUBECTL --request-timeout=180s -n apps-gateway patch secret cryptophys-wildcard-cert --type=merge -p "$PATCH_JSON" 2>&1 | head -1

# -------------------------------------------------------------------- step 8
log "Step 8/9: Writing to Vault"
TMPFILE=$(mktemp)
python3 -c "
import json, base64, sys
crt = sys.argv[1]
key = sys.argv[2]
payload = {'data': {'tls.crt': base64.b64encode(crt.encode() if isinstance(crt, str) else crt).decode(),
                    'tls.key': base64.b64encode(key.encode() if isinstance(key, str) else key).decode()}}
print(json.dumps(payload))
" "$NEW_CRT" "$NEW_KEY" > "$TMPFILE"
kubectl --context=admin@cryptophys-genesis-1 -n vault-system cp "$TMPFILE" vault-0:/tmp/cert-payload.json
kubectl --context=admin@cryptophys-genesis-1 -n vault-system exec vault-0 -- \
  wget -qO- --header="X-Vault-Token: $VAULT_TOKEN" --header="Content-Type: application/json" \
    --post-file=/tmp/cert-payload.json \
    "http://127.0.0.1:8200/v1/$VAULT_PATH" | python3 -m json.tool | head -5
rm -f "$TMPFILE"
log "  ✓ Vault updated"

# -------------------------------------------------------------------- step 9
log "Step 9/9: Verify live HTTPS"
sleep 5
LIVE_EXP=$(echo | timeout 5 openssl s_client -connect vault.cryptophys.work:443 -servername vault.cryptophys.work 2>/dev/null | \
  openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
if [ "$LIVE_EXP" = "$NEW_EXP" ]; then
  log "  ✓ vault.cryptophys.work serves the new cert (exp: $LIVE_EXP)"
else
  log "  ⚠ vault.cryptophys.work still serves old cert (live exp: $LIVE_EXP)"
  log "    The ingress-nginx controller caches the cert in memory. It should reload"
  log "    on the next cert-manager refresh interval (default 60s). Wait or run:"
  log "    kubectl rollout restart deploy/ingress-gateway-ingress-nginx-controller -n ingress-system"
fi

log ""
log "=== EMERGENCY CERT RENEWAL COMPLETE ==="
log "New cert: $NEW_NOTBEFORE → $NEW_EXP"
log "Run 'kubectl create job -n cert-manager --from=cronjob/cert-to-vault-sync manual-test' to verify the cron"
log "Run 'curl -sI https://vault.cryptophys.work/' to verify live HTTPS"
