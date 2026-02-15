# RUNBOOK — Gitea Health + Latency + Git Ops

## Tujuan

Validasi cepat apakah Gitea benar-benar sehat untuk operasi Git (fetch/pull/push path) dan bukan sekadar pod `Running`.

## One-command

```bash
/opt/cryptophys/tools/gitea_health_check.sh
```

## Output yang Dicek

Script mengecek:

- Runtime cluster:
  - Pod Gitea ready
  - Service/Ingress Gitea tersedia
  - Status Flux `36-gitea` + `platform-repo`
- HTTP smart-git endpoint (`info/refs`) internal + external dengan stress test
- `git ls-remote` internal + external dengan stress test
- Statistik latensi: `min/avg/p95/max`
- Verdict akhir: `PASS` / `FAIL`

## Exit Code

- `0`: PASS (tidak ada kegagalan internal)
- `1`: FAIL (ada kegagalan internal endpoint/git)

## Parameter Opsional

Contoh tuning jumlah iterasi:

```bash
HTTP_N=50 GIT_N=20 /opt/cryptophys/tools/gitea_health_check.sh
```

Variabel yang didukung:

- `NS_GITEA` (default `gitea`)
- `NS_FLUX` (default `flux-system`)
- `HOST` (default `gitea.cryptophys.work`)
- `REPO_PATH` (default `cryptophys.adm/platform-gitops.git`)
- `HTTP_N` (default `30`)
- `GIT_N` (default `15`)
- `TIMEOUT_S` (default `20`)

## Catatan Diagnostik

Jika `external` fail tapi `internal` pass:

- Kemungkinan masalah DNS/Cloudflare/TLS edge/network path, bukan engine Gitea.

Jika `internal` fail:

- Investigasi berurutan: Gitea pod log, PostgreSQL-HA, Valkey, Service endpoint, NetworkPolicy.
