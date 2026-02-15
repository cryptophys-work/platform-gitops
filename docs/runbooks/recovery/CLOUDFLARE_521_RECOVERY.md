# Cloudflare 521 Recovery (Ingress Public Edge)

## Goal
Cloudflare harus bisa connect ke origin via **public node IP** pada port **80/443**.

## Invariant
- Cloudflare DNS `A *.cryptophys.work` → semua **public IP control-plane**.
- Ingress-NGINX controller **listen di host**:
  - `hostNetwork: true`
  - `dnsPolicy: ClusterFirstWithHostNet`
  - `replicaCount: 3` (1 per control-plane)
  - `strategy.rollingUpdate.maxSurge=0` dan `maxUnavailable=1` untuk menghindari deadlock port 80/443 saat rollout.
  - Disable profiling dan pindahkan healthz port (menghindari konflik port host):
    - `--profiling=false`
    - `--healthz-port=11054` (probe juga harus ke port ini)
- Namespace `ingress` PSS di-set `privileged` (hostNetwork/host ports tidak ditolak).

## Verify
```bash
kubectl get ns ingress --show-labels
kubectl -n ingress get pods -o wide
kubectl -n ingress get svc ingress-gateway-ingress-nginx-controller -o wide
kubectl get ingress -A -o wide

# origin reachability (langsung ke node public IP)
curl -skI https://178.18.250.39/ | head
curl -skI https://207.180.206.69/ | head
curl -skI https://157.173.120.200/ | head
```

## If 521 happens again
1) Pastikan DNS Cloudflare masih resolve ke public node IP (bukan 10.x/MetalLB).
2) Pastikan ingress controller benar-benar running di control-plane dan listen hostNetwork (lihat pod spec).
3) Kalau rollout ingress macet: cek `strategy.maxSurge=0` (ini wajib).
