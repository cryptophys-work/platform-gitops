# ExternalSecrets Repair Plan

Summary:
This document lists missing Vault entries and the immediate remediation steps to restore ExternalSecrets reconciliation. Do NOT commit secrets into Git. Use the Vault CLI or ESO to seed values.

Priority fixes (seed these Vault paths):
- secret/data/apps/argocd/server  — argocd admin password and TLS certs
- secret/data/apps/gitea/ui-admin  — gitea admin creds for mirror syncs
- secret/data/platform/cloudflare/tunnel  — cloudflared credentials_json + tunnel_id
- secret/data/apps/trustedledger/postgres  — postgres user/password for trustedledger
- secret/data/apps/harbor/registry-redis  — redis password for harbor
- secret/data/apps/mesh/nats  — nats user/password for mesh

Recommended seeding commands (example):

# vault kv put secret/data/apps/argocd/server admin.password='<redacted>' admin.passwordMtime='2026-04-23T00:00:00Z'

Operational steps:
1. Confirm Vault is healthy and ESO can authenticate (kubectl get pods -n vault-system).
2. Seed the above paths using vault kv put or ESO-approved tooling. Avoid plaintext in repo.
3. For ExternalSecrets with creationPolicy: Merge, ensure a placeholder target Secret exists so merge can proceed (kubectl create secret generic <name> -n <ns> --dry-run=client -o yaml | kubectl apply -f -).
4. Watch ExternalSecrets controller logs and ExternalSecret status: kubectl get externalsecret -A -o wide; kubectl logs -n external-secrets deploy/externalsecrets-controller
5. Remove emergency placeholder Secrets after ESO has fully merged provider values.

Contact owners: argocd-admin, gitea-admin, platform-ops, trustedledger-team, registry-admin, mesh-team.

Notes:
- Do not write secrets to Git. This file is a runbook only.
- If any namespaces are Terminating, resolve cleanup before ExternalSecret can create or update Secrets there.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
