# Vault Unseal Procedure

## Overview
Vault uses Shamir secret sharing for unsealing. After restarts or seal events, Vault must be manually unsealed using 3 out of 5 unseal keys.

## Symptoms
- External Secrets fail with "Vault is sealed" (Code 503)
- ClusterSecretStore shows `ValidationFailed`
- ExternalSecrets show `SecretSyncedError`
- Applications continue running but cannot rotate/update secrets

## Unseal Keys Location
Unseal keys and privileged tokens MUST NOT be stored in this repository.

Store and retrieve break-glass materials from an approved secure system (HSM, cloud KMS, encrypted secret manager, or offline sealed storage) following your security policy.

**⚠️ SECURITY NOTICE:** These keys should be stored securely in production (e.g., encrypted storage, HSM, or key management service). Consider implementing Vault auto-unseal.

## Unseal Procedure

### 1. Check Vault Status
```bash
kubectl get pods -n vault-system
kubectl exec -n vault-system vault-0 -- vault status
```

If `Sealed: true`, proceed to unseal.

### 2. Unseal All Vault Pods
Each pod requires 3 keys (can be any 3 of the 5):

```bash
# Unseal vault-0
kubectl exec -n vault-system vault-0 -- vault operator unseal <UNSEAL_KEY_1>
kubectl exec -n vault-system vault-0 -- vault operator unseal <UNSEAL_KEY_2>
kubectl exec -n vault-system vault-0 -- vault operator unseal <UNSEAL_KEY_3>

# Unseal vault-1
kubectl exec -n vault-system vault-1 -- vault operator unseal <UNSEAL_KEY_1>
kubectl exec -n vault-system vault-1 -- vault operator unseal <UNSEAL_KEY_2>
kubectl exec -n vault-system vault-1 -- vault operator unseal <UNSEAL_KEY_3>

# Unseal vault-2
kubectl exec -n vault-system vault-2 -- vault operator unseal <UNSEAL_KEY_1>
kubectl exec -n vault-system vault-2 -- vault operator unseal <UNSEAL_KEY_2>
kubectl exec -n vault-system vault-2 -- vault operator unseal <UNSEAL_KEY_3>
```

**Note:** Only 2 keys needed after first key (shows `Unseal Progress: 2/3`), but third key completes unseal.

### 3. Verify Vault Status
```bash
for i in 0 1 2; do
  echo "=== vault-$i ==="
  kubectl exec -n vault-system vault-$i -- vault status | grep -E "Sealed|HA Mode"
done
```

Expected output:
```
Sealed: false
HA Mode: active    # vault-0
HA Mode: standby   # vault-1, vault-2
```

### 4. Verify External Secrets Integration

Check ClusterSecretStore:
```bash
kubectl get clustersecretstore vault-backend
# Expected: STATUS=Valid, READY=True
```

If still showing `ValidationFailed`, the ESO token may be invalid or the Vault policy may be wrong. Regenerate using the **canonical HCL** shipped in-cluster:

**Design:** `ClusterSecretStore` uses KV mount `secret` (v2). All `remoteRef.key` values (for example `apps/gitea/admin`) map to `secret/data/<key>`. Policies on separate mounts such as `apps/data/*` **do not** apply and must not be used for ESO.

**Sources of truth (GitOps):**

- Read-only policy for ESO: `platform/infrastructure/vault-system/policies/external-secrets-kv2-read.hcl` (Vault policy name: `external-secrets`).
- Break-glass KV writer (never for ESO): `platform/infrastructure/vault-system/policies/platform-kv2-bootstrap-write.hcl` (policy name: `platform-kv2-bootstrap`).
- Flux renders these into ConfigMap `vault-policy-hcl` in namespace `vault-system`.

```bash
# Export a privileged Vault token from secure storage (root or admin). Do not commit or paste into chat.
export VAULT_TOKEN=<SECURELY_RETRIEVED_VAULT_TOKEN>

# Install / refresh the read-only policy External Secrets uses
kubectl get configmap vault-policy-hcl -n vault-system -o jsonpath='{.data.external-secrets-kv2-read\.hcl}' | \
  kubectl exec -i -n vault-system vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" vault policy write external-secrets -

# (Optional break-glass) Install bootstrap writer — use only to vault kv put missing paths; revoke token after.
kubectl get configmap vault-policy-hcl -n vault-system -o jsonpath='{.data.platform-kv2-bootstrap-write\.hcl}' | \
  kubectl exec -i -n vault-system vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" vault policy write platform-kv2-bootstrap -

# Create a long-lived renewable read-only token for ESO (never attach platform-kv2-bootstrap to ESO)
NEW_TOKEN=$(kubectl exec -n vault-system vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" \
  vault token create -policy=external-secrets -ttl=8760h -renewable=true -format=json | jq -r '.auth.client_token')

kubectl create secret generic vault-eso-token \
  -n external-secrets \
  --from-literal=token="$NEW_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart -n external-secrets deployment/external-secrets
```

### 5. Verify ExternalSecrets
```bash
kubectl get externalsecrets -A | grep -E "NAMESPACE|gitea|headlamp"
# All should show STATUS=SecretSynced, READY=True
```

### 6. Vault Web UI: username & password (optional Layer 2)

Ingress uses **HTTP Basic Auth** (browser popup) as the first gate. For a **second** login inside the Vault UI (user/password instead of pasting a token), enable **`userpass`** and point the UI at it.

1. **Apply read policy for UI browsing** (from GitOps ConfigMap; idempotent):

   ```bash
   kubectl exec -n vault-system vault-0 -- sh -c 'vault policy write vault-ui-operator-read - <<EOF
   # paste contents of vault-ui-operator-read.hcl from vault-policy-hcl ConfigMap
   EOF'
   ```

   Or copy from: `platform-gitops/platform/infrastructure/vault-system/policies/vault-ui-operator-read.hcl`.

2. **Enable userpass** (once per cluster):

   ```bash
   kubectl exec -n vault-system vault-0 -- vault auth enable userpass
   ```

3. **Create an operator user** (choose a strong password; do not commit it):

   ```bash
   kubectl exec -n vault-system vault-0 -- \
     vault write auth/userpass/users/cryptophys.adm password='REPLACE_ME' policies=vault-ui-operator-read
   ```

4. **Set UI default login method to userpass** (Vault 1.11+):

   ```bash
   kubectl exec -n vault-system vault-0 -- \
     vault write sys/config/ui/login/default-auth method=userpass
   ```

5. Open the UI URL; complete **Basic Auth**, then sign in with **Method: Username** (user `cryptophys.adm`, password from step 3).

To revert to token-only in the UI:

```bash
kubectl exec -n vault-system vault-0 -- vault delete sys/config/ui/login/default-auth
```

## Prevention: Auto-Unseal

Consider implementing Vault auto-unseal for production:

1. **Transit Auto-Unseal**: Use another Vault cluster
2. **Cloud KMS**: AWS KMS, Azure Key Vault, GCP Cloud KMS
3. **HSM**: Hardware Security Module integration

Reference: https://developer.hashicorp.com/vault/docs/concepts/seal#auto-unseal

## Troubleshooting

### ClusterSecretStore stays ValidationFailed after unseal
- Check ESO token validity: `kubectl exec -n vault-system vault-0 -- vault token lookup $TOKEN`
- Regenerate token with correct policy (see step 4)
- Ensure ESO controller has restarted after token update

### ExternalSecrets stay in SecretSyncedError
- Wait 60 seconds for ESO controller to reconcile
- Force reconcile: `kubectl annotate externalsecret -n <namespace> <name> force-sync="$(date)"`
- Check ESO controller logs: `kubectl logs -n external-secrets deploy/external-secrets`

### Vault active node changes after unseal
- Normal behavior - Raft HA cluster elects new leader
- All pods should show `Sealed: false`
- Only one pod shows `HA Mode: active`, others show `standby`

## Recovery History

**2026-02-17:** Vault sealed after restart. Root cause: Shamir unseal requires manual intervention. Successfully unsealed all 3 pods and regenerated ESO token. Result: 14/14 ExternalSecrets synced, 100% cluster health restored.

## ESO token vs bootstrap (security model)

- **`vault-eso-token`** currently grants **read/write** access on KV mount `secret` (policy `external-secrets`) so both `ExternalSecret` and `PushSecret` can use the shared `ClusterSecretStore`. This is a broad permission surface; rotate and reduce it later if you split read vs write stores.
- **Bootstrap / remediation** may still use a separate privileged Vault session (for example `vault kv put secret/apps/gitea/admin ...`) via policy `platform-kv2-bootstrap`, but the cluster-wide ESO token is no longer read-only.
- **PushSecret targeting `ClusterSecretStore/vault-backend` is expected to work** once the live Vault policy and `vault-eso-token` have been refreshed to the current Git-managed policy.
- **Never** paste root tokens, unseal keys, or `vault-eso-token` values into chat, tickets, or Git.

## Security Follow-up (Mandatory)

If any unseal keys or privileged Vault tokens are ever committed to git:

1. Treat as credential compromise.
2. Rotate exposed tokens/keys immediately.
3. Invalidate downstream derived credentials.
4. Remove exposed material from repository history.
5. Record incident and remediation completion in security operations logs.
