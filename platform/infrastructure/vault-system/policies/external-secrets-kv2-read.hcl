# Policy: external-secrets (KV v2 mount "secret" only — matches ClusterSecretStore vault-backend path=secret)
# Apply: vault policy write external-secrets @external-secrets-kv2-read.hcl
# Token for ESO: vault token create -policy=external-secrets -ttl=8760h -renewable=true

path "secret/data/*" {
  capabilities = ["read"]
}

path "secret/metadata/*" {
  capabilities = ["list", "read"]
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
