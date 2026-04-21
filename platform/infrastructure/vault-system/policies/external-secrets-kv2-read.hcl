# Policy: external-secrets (KV v2 mount "secret" only — matches ClusterSecretStore vault-backend path=secret)
# Historical filename retained for compatibility; this policy now grants read/write
# so both ExternalSecret and PushSecret can use the shared ClusterSecretStore.
# Apply: vault policy write external-secrets @external-secrets-kv2-read.hcl
# Token for ESO: vault token create -policy=external-secrets -ttl=8760h -renewable=true

path "secret/data/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list"]
}

path "secret/metadata/*" {
  capabilities = ["create", "list", "read", "update", "patch", "delete"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "sys/mounts" {
  capabilities = ["read"]
}
