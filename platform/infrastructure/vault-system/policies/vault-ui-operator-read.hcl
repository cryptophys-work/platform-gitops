# Policy: vault-ui-operator-read — read-only Vault UI navigation (KV mount "secret" + mount listing).
# Attach to a userpass user (e.g. cryptophys.adm) after: vault auth enable userpass
# Apply: vault policy write vault-ui-operator-read @vault-ui-operator-read.hcl

path "sys/mounts" {
  capabilities = ["read"]
}

path "sys/internal/ui/mounts" {
  capabilities = ["read"]
}

path "secret/metadata/*" {
  capabilities = ["list", "read"]
}

path "secret/data/*" {
  capabilities = ["read"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
