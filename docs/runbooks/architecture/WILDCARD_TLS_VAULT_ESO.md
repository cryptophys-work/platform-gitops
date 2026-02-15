# Wildcard TLS (Vault + ExternalSecrets) Runbook

## Tujuan
- Hanya ada **1 TLS wildcard** untuk `*.cryptophys.work`.
- TLS secret di semua namespace **di-sync dari Vault** via External Secrets Operator (ESO).
- Ingress tidak lagi bergantung ke `cert-manager.io/cluster-issuer` (menghindari drift/521 saat issuer tidak ada).

## Sumber data (Vault)
- KV mount: `secret/` (v2)
- Path: `secret/apps/gitea/helm-values` (key: `values_yaml`)
- Path: `secret/apps/gitea/admin` (key: `username`, `password`)
- Path: `secret/platform/tls/cryptophys-wildcard` (key: `tls_crt`, `tls_key`)

## Manifest GitOps
- ESO wildcard TLS:
  - `infrastructure/secrets/externalsecret-wildcard-tls.yaml`
- Ingress standardized (TLS secretName = `cryptophys-wildcard-tls`):
  - `platform/infrastructure/networking/ingress-vault.yaml`
  - `platform/infrastructure/networking/ingress-hubble-ui.yaml`
  - `platform/infrastructure/networking/ingress-longhorn-ui.yaml`
  - `platform/infrastructure/networking/ingress-headlamp.yaml`

## Verifikasi (cluster)
```bash
kubectl -n external-secrets get pods
kubectl get clustersecretstore vault-backend

kubectl -n vault-secrets get externalsecret cryptophys-wildcard-tls
kubectl -n platform-ui get externalsecret cryptophys-wildcard-tls

kubectl -n vault-secrets get ingress vault -o jsonpath='{.spec.tls[0].secretName}{"\n"}'
kubectl -n kube-system get ingress hubble-ui -o jsonpath='{.spec.tls[0].secretName}{"\n"}'
kubectl -n platform-ui get ingress headlamp -o jsonpath='{.spec.tls[0].secretName}{"\n"}'
```

## Catatan Cloudflare 521
Jika origin sudah OK (curl langsung ke public IP node berhasil) tapi Cloudflare masih 521:
- Pastikan DNS record `A/CNAME` mengarah ke **public IP control-plane**, bukan `10.x` atau `10.100.x` (ClusterIP).
