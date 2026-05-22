# Deterministic YAML Naming Convention

## Schema

| Prefix | Category | Examples |
|--------|----------|----------|
| 01-* | CRDs & Base | `01-crds.yaml` |
| 02-* | Namespaces | `02-namespaces.yaml` |
| 03-* | Scheduling | `03-scheduling.yaml` |
| 04-* | Sources | `04-flux-sources.yaml` |
| 05-* | Controllers | `05-controllers.yaml` |
| 06-* | Database | `06-database.yaml` |
| 07-* | Certificates | `07-certificates.yaml` |
| 08-* | DNS | `08-dns-core.yaml` |
| 09-* | Security | `09-security-runtime.yaml` |
| 10-* | LoadBalancer | `10-metallb.yaml` |
| 11-* | Networking | `11-networking.yaml` |
| 12-* | Policies | `12-policies.yaml` |
| 13-* | Storage | `13-storage.yaml` |
| 14-* | Registry | `14-harbor.yaml` |
| 15-* | GitOps | `15-argocd.yaml` |
| 16-* | Observability | `16-observability.yaml` |
| 17-* | Compute | `17-ray.yaml` |
| 18-* | Gateway | `18-gateway.yaml` |

## Benefits

- **Deterministic**: Alphabetical = predictable order
- **Findable**: Category prefix makes searching easy
- **Maintainable**: Clear ownership boundaries
