# Cloudflare Tunnel (Wildcard) — Runbook

## Kenapa perlu
- Kita **tidak punya public IP khusus** untuk MetalLB.
- IP MetalLB `10.8.0.240` adalah IP private, **Cloudflare tidak bisa reach** dari internet → hasilnya `521`.
- Solusi yang deterministik: **Cloudflare Tunnel** (cloudflared) outbound dari cluster.

## Target desain
- DNS: `*.cryptophys.work` → CNAME ke `UUID.cfargotunnel.com`
- Routing: cloudflared meneruskan berdasarkan Host header ke ingress-nginx di cluster.

## Manifests GitOps
- Deployment cloudflared (default `replicas: 0` sampai secret siap):
  - `platform/infrastructure/networking/cloudflared/deployment.yaml`
- ExternalSecret cloudflared:
  - `infrastructure/secrets/externalsecret-cloudflared.yaml`

## Data yang harus ada di Vault
Path: `secret/platform/cloudflare/tunnel`
- `config_yaml` (config.yml)
- `credentials_json` (credentials.json)

Contoh `config.yml` (wildcard ke ingress-nginx):
```yaml
tunnel: <TUNNEL-UUID>
credentials-file: /etc/cloudflared/credentials.json
ingress:
  - hostname: "*.cryptophys.work"
    service: http://ingress-gateway-ingress-nginx-controller.ingress.svc.cluster.local:80
  - service: http_status:404
```

## Prosedur create tunnel (sekali saja)
1) Buat tunnel dari workstation admin (pakai `cloudflared` login):
```bash
cloudflared tunnel login
cloudflared tunnel create cryptophys-wildcard
cloudflared tunnel list
```

2) Route DNS wildcard ke tunnel:
```bash
cloudflared tunnel route dns cryptophys-wildcard "*.cryptophys.work"
```

3) Ambil file credentials:
Biasanya ada di:
`~/.cloudflared/<TUNNEL-UUID>.json`

4) Push config+credentials ke Vault (jalankan dari host yang punya akses Vault root/operator):
```bash
vault kv put secret/platform/cloudflare/tunnel \\
  config_yaml=@config.yml \\
  credentials_json=@<TUNNEL-UUID>.json \\
  updated_at="$(date -Is)"
```

5) Scale cloudflared:
```bash
kubectl -n cloudflare-tunnel scale deploy/cloudflared --replicas=2
```

## Verifikasi
```bash
kubectl -n cloudflare-tunnel get pods
kubectl -n cloudflare-tunnel logs deploy/cloudflared --tail=100
```
