# Vault Unseal Runbook (cryptophys)

Scope: pemulihan akses Vault setelah restart/upgrade, sebelum hardening/ESO.

Target cluster state (GitOps):
- Namespace: `vault-secrets`
- Workload: `StatefulSet/vault` (raft, HA enabled, 3 replicas)
- UI/Ingress: `vault.cryptophys.work`

## 0) Pre-check

```bash
kubectl -n vault-secrets get sts,pods -o wide
kubectl -n vault-secrets exec vault-0 -- vault status || true
```

Jika `Sealed: true`, lanjut ke unseal.

## 1) Pastikan init file yang benar (di host, bukan di repo)

Init file **tidak boleh** disimpan di repo Git. Di environment cryptophys biasanya tersimpan di host:

```bash
ls -la /opt/cryptophys/.secrets | rg 'vault-init-.*\\.json'
```

Gejala memakai init file yang salah:
- `vault operator unseal ...` pada key ke-3 gagal dengan error seperti:
  - `cipher: message authentication failed`

Jika itu terjadi, gunakan init file lain yang sesuai dengan instalasi Vault saat ini.

## 2) Unseal (manual, 3-of-5 shares)

Jalankan unseal untuk semua pod `vault-{0,1,2}` memakai 3 key pertama dari init file.

Contoh (ganti `VAULT_INIT_JSON`):

```bash
VAULT_INIT_JSON=/opt/cryptophys/.secrets/vault-init-YYYYMMDDThhmmssZ.json

for pod in vault-0 vault-1 vault-2; do
  echo "== unseal $pod"
  jq -r '.unseal_keys_b64[0:3][]' "$VAULT_INIT_JSON" | while read -r k; do
    kubectl -n vault-secrets exec "$pod" -- vault operator unseal "$k"
  done
done
```

Catatan:
- Jangan copy-paste key ke chat/log.
- Jika key1..3 tidak cocok, Vault akan kembali `Unseal Progress 0/3` setelah error; lanjutkan dengan init file yang benar.

## 3) Verifikasi leader/standby

```bash
for pod in vault-0 vault-1 vault-2; do
  echo "== $pod"
  kubectl -n vault-secrets exec "$pod" -- vault status | rg -n "Sealed|HA Mode|Active Node Address|Storage Type|Raft"
done
```

Ekspektasi:
- Tepat 1 pod `HA Mode: active`
- Sisanya `HA Mode: standby`
- Semua `Sealed: false`

## 4) Smoke test via ingress

```bash
curl -sk https://vault.cryptophys.work/v1/sys/health
```

Catatan: jika request masuk ke standby, response bisa `\"standby\": true` (ini normal).

