# Platform GitOps 🛡️

This repository manages the foundational platform infrastructure and cluster configurations for the Cryptophys network using a GitOps model powered by Flux.

## 🏗️ Architecture

The GitOps architecture follows a three-repository pattern for separation of concerns:

- **`platform-gitops`** (this repo): Core infrastructure (Ingress, DNS, Database operators, Security policies, Cert management).
- **`apps-gitops`**: Application deployments, middleware configurations, and business logic services via ArgoCD.
- **`ssot-core`**: The Single Source of Truth for schemas, cross-service contracts, and global operational documentation.

## 🚀 Bootstrap

Infrastructure is bootstrapped via Flux. The root application starts by pointing to the repository's internal mTLS-protected endpoint:

- `https://giteainternal.cryptophys.work/cryptophys-work/platform-gitops.git`
- `https://giteainternal.cryptophys.work/cryptophys-work/apps-gitops.git`
- `https://giteainternal.cryptophys.work/cryptophys-work/ssot-core.git`

## 🛠️ Components

### 1. Controllers & Operators
- **Ingress-Nginx**: Internal and external traffic management.
- **Cert-Manager**: Automated TLS certificate issuance via Let's Encrypt (External) and SPIRE (Internal).
- **External-Secrets**: Integration with HashiCorp Vault for secure secret injection.
- **Kyverno**: Admission control and security policy enforcement.

### 2. Infrastructure Services
- **Gitea**: Internal Git hosting for GitOps loops.
- **Postgres-Operator (Zalando)**: High-availability database clusters.
- **Redis**: Shared caching layer for platform components.

### 3. Security & Observability
- **SPIRE**: Workload identity (SPIFFE) for mTLS between infrastructure components.
- **Cilium**: Network policies and eBPF-based observability.
- **Falco/Tetragon**: Runtime security monitoring.

## 📁 Directory Structure

```text
.
├── clusters/             # Cluster-specific Flux configurations
│   └── talos-prod/       # Production cluster root
├── platform/             # Reusable infrastructure components
│   ├── base/             # Common base manifests
│   ├── infrastructure/   # Core services (DB, Git, Ingress)
│   ├── networking/       # CNI, DNS, and Mesh configs
│   └── security/         # SPIRE, Vault, and Policies
└── hack/                 # Automation and validation scripts
```

## 🔐 Security Standards

All internal communications between infrastructure components (e.g., ArgoCD to Gitea) are protected by:
1. **mTLS**: Enforced via SPIRE-issued certificates.
2. **CiliumNetworkPolicy**: Least-privileged access at L3/L4/L7.
3. **Vault**: Centralized secret management.
