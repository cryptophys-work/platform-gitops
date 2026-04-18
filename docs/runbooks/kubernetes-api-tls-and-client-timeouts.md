# Kubernetes API: TLS handshake timeouts and client resilience

## Purpose

Operators see intermittent failures such as:

- `kubectl` / `flux`: `net/http: TLS handshake timeout` to `https://k8s.cryptophys.work:6443`
- Flux `Kustomization` health: Namespace status stuck `Unknown`, or dry-run timeouts (Harbor Redis, Kyverno webhooks)

These symptoms usually share a root cause: **apiserver overload**, **path MTU issues on the public VIP path**, or **short client deadlines** under load—not necessarily a broken certificate.

## Severity

**High** when control-plane nodes flap or the VIP path is lossy: admission webhooks (Kyverno) and Flux reconciliation fail in cascade.

## Quick checks

1. From the workstation:

   ```bash
   curl -vk --connect-timeout 5 --max-time 20 https://k8s.cryptophys.work:6443/livez
   ```

   Expect `401`/`403` without a client cert, but the TCP+TLS handshake must complete quickly.

2. From the same shell as automation:

   ```bash
   kubectl get --raw='/readyz?verbose' --request-timeout=30s
   ```

3. If the public VIP is flaky but the mesh is reachable, compare latency to a **break-glass** endpoint (WireGuard / internal LB) documented out-of-band for your environment.

## Mitigations

### kubectl / flux CLI

- Prefer explicit deadlines on hot paths: `kubectl --request-timeout=60s …`, `flux get …` after API is healthy.
- Avoid running many parallel `kubectl` scripts against the same apiserver during incidents.

### Flux `Kustomization` timeouts

- `01-namespaces` and `41-harbor` use extended `spec.timeout` values in `clusters/cryptophys-genesis/kustomization/` so slow health checks and Helm dry-runs do not fail spuriously when the API is briefly slow.

### Kyverno admission stability

- `platform/infrastructure/policy/kyverno-release.yaml` configures a **longer admission `startupProbe` timeout** and enables **`apiPriorityAndFairness`** on the admission controller so brief apiserver pressure is less likely to starve the HTTPS `:9443` probes (which previously used a 1s probe timeout by default).

## Related

- Kyverno webhook / policy stage: `15-policy`, `46-security-obs`
- Harbor: `41-harbor`
