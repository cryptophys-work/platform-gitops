# Harbor Split-Ingress Fix

## Context
The Harbor registry was returning 502 Bad Gateway errors for the `/v2/` path. Diagnosis showed that the Nginx Ingress was attempting to use HTTPS for the upstream connection to the registry pod on port 5443, while the registry pod was only configured for HTTP on that port.

## Solution
Implemented a "Split Ingress" strategy using a Kustomize overlay. This approach creates two separate Ingress resources:
1. `registry-harbor-ingress-v2`: Dedicated to the `/v2/` path, using `nginx.ingress.kubernetes.io/backend-protocol: "HTTP"`.
2. `registry-harbor-ingress-ui`: Handles all other paths (`/api/`, `/service/`, `/c/`, `/`), using `nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"`.

The original Helm-generated Ingress (`registry-harbor-ingress`) is deleted by the Kustomize overlay to prevent conflicts.

## Persistence
The ArgoCD Application `registry` has been updated to point to the `overlays/split-ingress` directory in the `registry-gitops` repository. All manifests are committed to Git.

## Validation
1. Verify Ingress resources:
   ```bash
   kubectl -n registry get ingress | grep registry-harbor
   ```
   Expect `registry-harbor-ingress-v2` and `registry-harbor-ingress-ui` to exist.

2. Test Registry Path (/v2/):
   ```bash
   kubectl -n registry run netcheck-lb --rm -it --restart=Never --image=curlimages/curl:8.5.0 -- \
     sh -lc 'curl -sk --resolve registry.cryptophys.work:443:10.8.0.240 https://registry.cryptophys.work/v2/ -D- -o /dev/null | head -n 20'
   ```
   Expect `HTTP/2 401`.

3. Test API Path:
   ```bash
   kubectl -n registry run netcheck-api --rm -it --restart=Never --image=curlimages/curl:8.5.0 -- \
     sh -lc 'curl -sk --resolve registry.cryptophys.work:443:10.8.0.240 https://registry.cryptophys.work/api/v2.0/ping -D- -o /dev/null | head -n 20'
   ```
   Expect `HTTP/2 200`.
