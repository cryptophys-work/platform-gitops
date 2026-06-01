# cert-to-vault-sync

**Purpose:** Sync `cert-manager/platform-wildcard-tls` (written by cert-manager) → `secret/data/platform/tls/cryptophys-wildcard` in Vault, which is the source of truth for 12 ExternalSecret resources across the cluster.

**Why a CronJob (not PushSecret):**
ESO's `PushSecret` CRD requires the source K8s secret to have no owner reference. Since cert-manager owns `platform-wildcard-tls`, PushSecret fails with `secret not managed by external-secrets`. The CronJob bypasses this by reading the K8s secret directly and writing to Vault via HTTP API.

**Setup (operator, one-time):**

```bash
# 1. Create a long-lived Vault token with write policy
VAULT_TOKEN=$(kubectl exec -n vault-system vault-0 -- \
  sh -c "wget -qO- --header='X-Vault-Token: ${VAULT_ROOT_TOKEN}' \
  http://127.0.0.1:8200/v1/auth/token/create" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['auth']['client_token'])")

# 2. Create the Secret in the cluster
kubectl create secret generic vault-sync-token -n cert-manager \
  --from-literal=token="$VAULT_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
```

**Trigger the sync manually (for testing):**
```bash
kubectl create job -n cert-manager --from=cronjob/cert-to-vault-sync manual-test
kubectl logs -n cert-manager -l job-name=manual-test
```

**Verify the sync works:**
```bash
# Check Vault was updated
kubectl exec -n vault-system vault-0 -- sh -c "
  wget -qO- --header='X-Vault-Token: $VAULT_TOKEN' \
  http://127.0.0.1:8200/v1/secret/data/platform/tls/cryptophys-wildcard
" | python3 -c "import json,sys; d=json.load(sys.stdin); print('ver:', d['data']['metadata']['version'])"
```

**Schedule:** Every 15 minutes (`*/15 * * * *`).

**Idempotency:** Each run bumps the Vault version, even if cert hasn't changed. 12 ESO `platform-wildcard-tls` consumers will sync on their next refresh (1h or 24h).
