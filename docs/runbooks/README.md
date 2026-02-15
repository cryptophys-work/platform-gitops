# Cryptophys Single Source of Truth (SSOT) Core

This repository contains the immutable contracts, schemas, and governance rules for the Cryptophys Universe.

## Architecture

The GitOps strategy is split into three repositories:

1.  **`cryptophys-ssot-core`** (This repo):
    *   **Contracts:** API definitions, data models (`contracts/`).
    *   **Schemas:** JSON schemas for validation (`schema/`).
    *   **Ledger Rules:** Immutable rules for the trusted ledger (`ledger/`).
    *   **AIDE Playbooks:** Remediation logic for the Autonomous Infrastructure Defense Engine (`aide-playbooks/`).

2.  **`cryptophys-platform-gitops`** (Flux):
    *   **Clusters:** Flux bootstrap configuration (`clusters/talos-prod/`).
    *   **Infrastructure:** Base infrastructure components managed by Flux (`infrastructure/`).
        *   Order: `00-crds` -> `10-controllers` -> `20-policy` -> `30-storage` -> `40-observability` -> `90-aide-sensors`.

3.  **`cryptophys-apps-gitops`** (ArgoCD):
    *   **Apps:** Domain-specific applications (`apps/`).
    *   **ArgoCD:** Projects and ApplicationSets (`argocd/`).

## Governance

*   **Kyverno Policies:** Enforce security standards. Critical system namespaces (`kube-system`, `longhorn-system`, `cilium-system`) MUST be excluded from restrictive policies to prevent deadlocks.
*   **Immutable Infrastructure:** Changes to `ssot-core` trigger validation pipelines.

## Policy Paths (Flux Consumers)

These paths are consumed by Flux Kustomizations:

- `policies/kyverno/base`
- `policies/kyverno/enforce-business`
- `policies/kyverno/exception-governance`
- `policies/gatekeeper/templates`
- `policies/gatekeeper/constraints`
- `policies/gatekeeper/enforce-business`
- `ops/waiver-cleanup`

## Network & DNS

*   **Cilium:** Manages CNI and mesh (`wg0`). Egress to public DNS (`1.1.1.1`) requires correct routing table configuration on Talos nodes.
*   **CoreDNS:** Configured with `autopath` and `pods verified` for stability.
