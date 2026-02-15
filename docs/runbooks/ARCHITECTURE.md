# Cryptophys Platform Architecture (Current)

## Core components

- **Kubernetes**: Talos 5-node cluster (control-plane on `cortex`, workers on `cerebrum/corpus/aether/campus`).
- **Ingress**: `ingress-nginx` exposes platform endpoints (`*.cryptophys.work`).
- **Git (source of truth)**: Gitea (`https://gitea.cryptophys.work`) hosts the monorepo used by ArgoCD apps.
- **GitOps (desired state)**: ArgoCD (`platform-gitops` namespace) applies manifests from the monorepo.
- **Build (CI inside cluster)**: Tekton builds container images from Gitea webhooks.
- **Registry**: Harbor (`registry.cryptophys.work`) stores built images.
- **Secrets**: HashiCorp Vault (`https://vault.cryptophys.work`) + External Secrets Operator (ESO) materializes secrets into namespaces.
- **Policy**: Kyverno enforces baseline pod security + organizational rules (labels, resources, etc).
- **Observability**: (Linkerd/metrics/logs) for runtime visibility.
- **TrustedLedger**: append-only event log for build/deploy provenance (target state).

## Primary delivery loop (intended)

1. Developer pushes code to **Gitea**.
2. Gitea emits a webhook to Tekton Triggers/EventListener.
3. Tekton Pipeline:
+   - clones repo
   - builds image (BuildKit/buildx)
   - scans (Trivy)
   - signs (Cosign)
   - pushes to Harbor (`registry.cryptophys.work/library/<app>:<commit-sha>`)
4. ArgoCD reconciles deployment manifests (Helm/Kustomize/raw) from Gitea and deploys the new image.

## Secrets model (current)

- Vault runs as a single replica (file backend on PVC) with TLS terminated at Ingress.
- ESO uses **Vault Kubernetes Auth** (role `external-secrets`) to read from **KV v2** mount `kv/`.
- Apps pull secrets via `ExternalSecret` / `ClusterSecretStore vault`:
  - Example: `platform-ui/ExternalSecret headlamp-basic-auth` reads `kv/platform-ui/headlamp-basic-auth`.

## Known operational constraints (current)

- **Gitea Git operations can deadlock** (push/pull/fetch hangs) which blocks institutional GitOps updates.
- Some upstream images (e.g. `gcr.io/...`) may be blocked or require mirroring; prefer mirroring into Harbor.
- Kyverno + PodSecurity `restricted` can block controllers unless their manifests set compliant security contexts.

## Hardening roadmap (next)

- Vault: migrate to **Raft (HA)** + **auto-unseal** (KMS or transit), disable Shamir in day-2 ops.
- Auth: add **OIDC** (Dex/Keycloak/Gitea) and operator-only policies (avoid root).
- Supply-chain: enforce **SBOM + provenance + signature** gates before GitOps deploy:
  - Tekton “gates” stage (policy checks, verify attestation, verify signature)
  - Kyverno `verifyImages` (and/or policy controller) in-cluster
  - TrustedLedger events for build/scan/sign/deploy.

