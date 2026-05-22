# cryptophys-work Cluster

**Status:** Active - Single cluster for cryptophys-work organization

## Structure (Deterministic & World-Class)

```
clusters/cryptophys-work/
├── base/                    # Shared cluster configuration
├── overlays/
│   ├── production/          # Production environment
│   └── staging/             # Staging environment (future)
└── components/              # Reusable configuration components
```

## Naming Convention

All manifests use deterministic alphabetical naming:

| Prefix | Purpose |
|--------|---------|
| 01-* | CRDs and base resources |
| 02-* | Core system components |
| 03-* | Infrastructure |
| 04-* | Security policies |
| 05-* | Applications |
| 06-* | Observability |

## Commands

```bash
# Apply base configuration
flux reconcile source git flux-system -n flux-system

# Check production overlay
flux get kustomizations -A

# Validate
kubeconform -strict clusters/cryptophys-work
```

## Last Updated
Auto-generated as part of world-class GitOps initiative
