# Vault Unseal & Recovery Procedure 🔐

Vault uses Shamir secret sharing for unsealing. After restarts or seal events, Vault must be manually unsealed using 3 out of 5 unseal keys.

## 🚩 Symptoms of a Sealed Vault
- External Secrets fail with "Vault is sealed" (Code 503)
- ClusterSecretStore shows `ValidationFailed`
- ExternalSecrets show `SecretSyncedError`
- Applications continue running but cannot rotate/update secrets

## Unseal Keys Location
Unseal keys and privileged tokens MUST NOT be stored in this repository.
Store and retrieve break-glass materials from an approved secure system (HSM, cloud KMS, encrypted secret manager, or offline sealed storage) following your security policy.

**⚠️ SECURITY NOTICE:** These keys should be stored securely in production (e.g., encrypted storage, HSM, or key management service). Consider implementing Vault auto-unseal.

## 🛠️ Step-by-Step Unseal

### 1. Identify Sealed Pods
```bash
kubectl get pods -n vault-system -l app.kubernetes.io/name=vault
```

### 2. Run Unseal Command
Each pod requires 3 keys (can be any 3 of the 5):
```bash
# Repeat for vault-0, vault-1, vault-2
kubectl exec -it -n vault-system vault-0 -- vault operator unseal
# Enter key 1, repeat for key 2, then key 3
```

## 🔑 Secret Store Recovery

If still showing `ValidationFailed`, the ESO token may be invalid or the Vault policy may be wrong. Regenerate using the **canonical HCL** shipped in-cluster:

### 3. Initialize HCL Policies
```bash
# Export a privileged Vault token from secure storage (root or admin). Do not commit or paste into chat.
export VAULT_TOKEN=<SECURELY_RETRIEVED_VAULT_TOKEN>

# Write External Secrets policy
cat platform/infrastructure/vault-system/policies/external-secrets-kv2-read.hcl | \
  kubectl exec -i -n vault-system vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" vault policy write external-secrets -

# (Optional break-glass) Install bootstrap writer — use only to vault kv put missing paths; revoke token after.
cat platform/infrastructure/vault-system/policies/platform-kv2-bootstrap-write.hcl | \
  kubectl exec -i -n vault-system vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" vault policy write platform-kv2-bootstrap -
```

### 4. Rotate ESO Token
```bash
# Create a long-lived renewable read-only token for ESO (never attach platform-kv2-bootstrap to ESO)
NEW_TOKEN=$(kubectl exec -n vault-system vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" \
  vault token create -policy=external-secrets -ttl=8760h -renewable=true -format=json | jq -r '.auth.client_token')

# Update the secret in the cluster
kubectl create secret generic vault-eso-token \
  --namespace apps-system \
  --from-literal=token="$NEW_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 5. Verify Synchronization
```bash
kubectl annotate externalsecret -n apps-system --all force-sync=$(date +%s)
kubectl get externalsecret -n apps-system
```

### 6. Vault Web UI: username & password (optional Layer 2)
Ingress uses **HTTP Basic Auth** (browser popup) as the first gate. For a **second** login inside the Vault UI (user/password instead of pasting a token), enable **`userpass`** and point the UI at it.

1. **Enable auth method**: `vault auth enable userpass`
2. **Apply UI policy**: `vault policy write vault-ui-operator-read platform/infrastructure/vault-system/policies/vault-ui-operator-read.hcl`
3. **Create an operator user** (choose a strong password; do not commit it):
     `vault write auth/userpass/users/cryptophys.adm password='<SECURE_PASSWORD>' policies=vault-ui-operator-read`
4. **Ensure Ingress is healthy**: Check `platform/infrastructure/vault-system/vault.yaml` for Ingress annotations.
5. **Open the UI URL**; complete **Basic Auth**, then sign in with **Method: Username** (user `cryptophys.adm`, password from step 3).

To revert to token-only in the UI:
`vault auth disable userpass`

---

## 🪵 Maintenance Log
- **2026-02-17:** Vault sealed after restart. Root cause: Shamir unseal requires manual intervention. Successfully unsealed all 3 pods and regenerated ESO token. Result: 14/14 ExternalSecrets synced, 100% cluster health restored.

## 📝 Troubleshooting FAQ
**Q: My ExternalSecret shows `SecretSyncedError`.**
- Check ESO token validity: `kubectl exec -n vault-system vault-0 -- vault token lookup $TOKEN`
- Regenerate token with correct policy (see step 4)
- Ensure ESO controller has restarted after token update

## ESO token vs bootstrap (security model)
- **`vault-eso-token`** currently grants **read/write** access on KV mount `secret` (policy `external-secrets`) so both `ExternalSecret` and `PushSecret` can use the shared `ClusterSecretStore`. This is a broad permission surface; rotate and reduce it later if you split read vs write stores.
- **Bootstrap / remediation** may still use a separate privileged Vault session (for example `vault kv put secret/apps/gitea/admin ...`) via policy `platform-kv2-bootstrap`, but the cluster-wide ESO token is no longer read-only.
- **PushSecret targeting `ClusterSecretStore/vault-backend` is expected to work** once the live Vault policy and `vault-eso-token` have been refreshed to the current Git-managed policy.

---
**REMINDER:** Never paste root tokens, unseal keys, or `vault-eso-token` values into chat, tickets, or Git.

If any unseal keys or privileged Vault tokens are ever committed to git:
1. Revoke the token immediately.
2. Rotate ALL secrets that the token could access.
3. Perform a Vault re-key if unseal keys were leaked.
