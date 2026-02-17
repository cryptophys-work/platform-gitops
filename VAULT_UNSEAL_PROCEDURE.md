# Vault Unseal Procedure

## Overview
Vault uses Shamir secret sharing for unsealing. After restarts or seal events, Vault must be manually unsealed using 3 out of 5 unseal keys.

## Symptoms
- External Secrets fail with "Vault is sealed" (Code 503)
- ClusterSecretStore shows `ValidationFailed`
- ExternalSecrets show `SecretSyncedError`
- Applications continue running but cannot rotate/update secrets

## Unseal Keys Location
Keys stored in: `/root/.copilot/session-state/317d4b09-76b2-4b42-84ce-cdab279d8601/files/vault-init-new.json`

```json
{
  "unseal_keys_b64": [
    "eQnzjzHWylYDrI1pxUkGet33t1YtwCFRlF45OjWCnTm2",
    "x/rHbduGziqteIoDe0RBFKKEiFnJceBegDf9Qk04zRQV",
    "peS+JvQFVJwtZWLiqSzEREddp7oRgo3oumc6oBTfcBdM",
    "w19GhQ948J7ZqepBZos+zLgM058+OiUkNRc5ySdSk6Qb",
    "QuI0lpMb4qVrj14c/dm7DXd/RzMvLBdcsHUEoDAGZVxZ"
  ],
  "unseal_threshold": 3,
  "root_token": "hvs.0mINJZmq1wGLTFTtgkdETN8Z"
}
```

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
kubectl exec -n vault-system vault-0 -- vault operator unseal eQnzjzHWylYDrI1pxUkGet33t1YtwCFRlF45OjWCnTm2
kubectl exec -n vault-system vault-0 -- vault operator unseal x/rHbduGziqteIoDe0RBFKKEiFnJceBegDf9Qk04zRQV
kubectl exec -n vault-system vault-0 -- vault operator unseal peS+JvQFVJwtZWLiqSzEREddp7oRgo3oumc6oBTfcBdM

# Unseal vault-1
kubectl exec -n vault-system vault-1 -- vault operator unseal eQnzjzHWylYDrI1pxUkGet33t1YtwCFRlF45OjWCnTm2
kubectl exec -n vault-system vault-1 -- vault operator unseal x/rHbduGziqteIoDe0RBFKKEiFnJceBegDf9Qk04zRQV
kubectl exec -n vault-system vault-1 -- vault operator unseal peS+JvQFVJwtZWLiqSzEREddp7oRgo3oumc6oBTfcBdM

# Unseal vault-2
kubectl exec -n vault-system vault-2 -- vault operator unseal eQnzjzHWylYDrI1pxUkGet33t1YtwCFRlF45OjWCnTm2
kubectl exec -n vault-system vault-2 -- vault operator unseal x/rHbduGziqteIoDe0RBFKKEiFnJceBegDf9Qk04zRQV
kubectl exec -n vault-system vault-2 -- vault operator unseal peS+JvQFVJwtZWLiqSzEREddp7oRgo3oumc6oBTfcBdM
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

If still showing `ValidationFailed`, the ESO token may be invalid. Regenerate:

```bash
# Login with root token
kubectl exec -n vault-system vault-0 -- vault login hvs.0mINJZmq1wGLTFTtgkdETN8Z

# Create policy for External Secrets (if not exists)
kubectl exec -n vault-system vault-0 -- sh -c 'export VAULT_TOKEN=hvs.0mINJZmq1wGLTFTtgkdETN8Z && vault policy write external-secrets - <<EOF
path "secret/data/*" {
  capabilities = ["read"]
}
path "secret/metadata/*" {
  capabilities = ["list", "read"]
}
path "apps/data/*" {
  capabilities = ["read"]
}
path "apps/metadata/*" {
  capabilities = ["list", "read"]
}
path "platform/data/*" {
  capabilities = ["read"]
}
path "platform/metadata/*" {
  capabilities = ["list", "read"]
}
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF'

# Generate new token
NEW_TOKEN=$(kubectl exec -n vault-system vault-0 -- sh -c 'export VAULT_TOKEN=hvs.0mINJZmq1wGLTFTtgkdETN8Z && vault token create -policy=external-secrets -ttl=0 -format=json' | jq -r '.auth.client_token')

# Update secret
kubectl create secret generic vault-eso-token \
  -n external-secrets \
  --from-literal=token="$NEW_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart ESO controller
kubectl rollout restart -n external-secrets deployment/external-secrets
```

### 5. Verify ExternalSecrets
```bash
kubectl get externalsecrets -A | grep -E "NAMESPACE|gitea|headlamp"
# All should show STATUS=SecretSynced, READY=True
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
