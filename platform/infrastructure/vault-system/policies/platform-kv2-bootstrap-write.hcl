# Policy: platform-kv2-bootstrap — break-glass KV writes on mount "secret" ONLY.
# Do NOT attach this policy to vault-eso-token. Use root or human admin token, then revoke.
# Apply: vault policy write platform-kv2-bootstrap @platform-kv2-bootstrap-write.hcl
#
# After populating secrets, prefer: vault token revoke -self

path "secret/data/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list"]
}

path "secret/metadata/*" {
  capabilities = ["list", "read", "delete"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
