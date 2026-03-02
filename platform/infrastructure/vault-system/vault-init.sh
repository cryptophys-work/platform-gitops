#!/bin/sh
# vault-init.sh - Deterministic Vault Initializer for Cryptophys Genesis

# Exit on any error
set -e

# --- Configuration ---
VAULT_NAMESPACE="vault"
VAULT_POD_LABEL="app.kubernetes.io/name=vault"
MAX_RETRIES=30
RETRY_DELAY=10

# --- Wait for Vault Pod to be Ready ---
echo ">>> Waiting for Vault pod to become ready in namespace '$VAULT_NAMESPACE'..."
retries=0
while [ "$(kubectl get pods -n $VAULT_NAMESPACE -l $VAULT_POD_LABEL -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}')" != "True" ]; do
  if [ $retries -ge $MAX_RETRIES ]; then
    echo "ERROR: Timed out waiting for Vault pod. Aborting."
    exit 1
  fi
  echo "  - Vault not ready yet. Retrying in $RETRY_DELAY seconds... (Attempt $((retries + 1))/$MAX_RETRIES)"
  sleep $RETRY_DELAY
  retries=$((retries + 1))
done
echo ">>> Vault pod is Ready."

# --- Exec into Vault Pod to Run Setup ---
VAULT_POD_NAME=$(kubectl get pods -n $VAULT_NAMESPACE -l $VAULT_POD_LABEL -o jsonpath='{.items[0].metadata.name}')
echo ">>> Found Vault pod: $VAULT_POD_NAME"

echo ">>> Executing Vault setup script inside the pod..."
kubectl -n $VAULT_NAMESPACE exec $VAULT_POD_NAME -- /bin/sh -c '
  # Exit on any error within the pod script
  set -e

  # Login using Kubernetes Service Account Auth
  # (This assumes the auth method was enabled via Helm values)
  echo "  - Logging into Vault using K8s auth..."
  vault login -method=kubernetes role=vault-auth-role

  # --- Enable KV Secrets Engine at /secret ---
  # Use -path to avoid conflicts if it already exists
  if ! vault secrets list | grep -q "secret/"; then
    echo "  - Enabling KV v2 secrets engine at path '''secret/'''..."
    vault secrets enable -path=secret kv-v2
  else
    echo "  - KV v2 secrets engine at path '''secret/''' already enabled."
  fi

  # --- Create placeholder secrets (Idempotent PUT) ---
  echo "  - Creating placeholder secret for '''secret/cryptophys/execution'''..."
  vault kv put secret/cryptophys/execution placeholder="replace-with-real-token"

  echo "  - Creating placeholder secret for '''secret/cryptophys/identity'''..."
  vault kv put secret/cryptophys/identity placeholder="replace-with-real-token"
  
  echo "  - Creating placeholder secret for '''secret/apps/dash/keycloak'''..."
  vault kv put secret/apps/dash/keycloak placeholder="replace-with-real-token"

  echo ">>> Vault initialization complete."
'
