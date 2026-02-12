# Longhorn CRD Adoption Recovery (Flux/Helm)

Gunakan runbook ini saat `HelmRelease longhorn` gagal dengan pesan:

`exists and cannot be imported into the current release: invalid ownership metadata`

## Kapan Dipakai

- Setelah reset cluster / reinstall Longhorn
- CRD `*.longhorn.io` sudah ada, tapi belum memiliki metadata ownership Helm

## Prosedur

1) Verifikasi error:

```bash
kubectl -n longhorn-system get helmrelease longhorn -o custom-columns=NAME:.metadata.name,READY:.status.conditions[-1].status,MESSAGE:.status.conditions[-1].message
```

2) Adopsi semua CRD Longhorn ke release Helm:

```bash
for crd in $(kubectl get crd -o name | grep '\.longhorn\.io$'); do
  kubectl annotate "$crd" meta.helm.sh/release-name=longhorn meta.helm.sh/release-namespace=longhorn-system --overwrite
  kubectl label "$crd" app.kubernetes.io/managed-by=Helm --overwrite
done
```

3) Trigger reconcile ulang:

```bash
kubectl -n longhorn-system annotate helmrelease longhorn reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
kubectl -n flux-system annotate kustomization 30-storage reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
```

4) Verifikasi sukses:

```bash
kubectl -n longhorn-system get helmrelease longhorn -o custom-columns=NAME:.metadata.name,READY:.status.conditions[-1].status,MESSAGE:.status.conditions[-1].message
kubectl -n longhorn-system get pods
kubectl get pvc -A
```

## Hasil Sukses

- `HelmRelease/longhorn` status `READY=True`
- Semua pod `longhorn-system` `Running`
- PVC/PV kembali `Bound`
