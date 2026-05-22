# platform-gitops Structure Improvement Plan

## Current Issues
1. **Fragile numeric prefixes**: 05-, 10-, 15- ordering is non-deterministic
2. **No base/overlay pattern**: Missing clear separation for environments
3. **Mixed concerns**: Infrastructure, apps, and platform in same folders
4. **478 YAML files**: Need better organization

## Recommended Structure (Deterministic & World-Class)

```
platform-gitops/
├── README.md                        # Repo documentation
├── clusters/
│   ├── base/                        # Base cluster configs (applies to all)
│   │   ├── kustomization.yaml
│   │   ├── flux-system/
│   │   └── crds/
│   ├── overlays/
│   │   ├── talos-prod/              # Production specific
│   │   │   ├── kustomization.yaml   # Import from base + patches
│   │   │   ├── patches/             # Only diffs from base
│   │   │   └── image-overrides/     # Image version pins
│   │   └── cryptophys-genesis/      # Genesis cluster
│   │       └── patches/
│   └── templates/                   # Reusable components
├── platform/
│   ├── infrastructure/
│   │   ├── base/                    # Infrastructure base
│   │   ├── networking/
│   │   ├── storage/
│   │   └── compute/
│   ├── security/                    # Security policies
│   └── observability/               # Monitoring stack
├── apps/
│   ├── base/                        # Application base configs
│   └── overlays/
├── automation/
│   ├── scripts/
│   └── workflows/                   # GitOps automation
├── hack/
│   └── Makefile                     # Development tooling
└── docs/
    └── architecture/                # Architecture decisions
```

## Deterministic Naming Convention

### ❌ Current (Fragile)
```
05-sources.yaml
10-controllers.yaml
15-security-runtime.yaml
```

### ✅ Improved (Alphabetical + Semantic)
```
01-crds.yaml                         # Always apply CRDs first
02-base-system.yaml                  # Core system components
03-networking-cni.yaml
04-storage-class.yaml
05-security-policies.yaml
06-observability-metrics.yaml
07-app-of-apps.yaml                  # ArgoCD application of applications
```

## Action Items

1. **[High]** Adopt base/overlay pattern for clusters
2. **[High]** Rename YAML files to semantic naming
3. **[Medium]** Create platform/base with reusable components
4. **[Medium]** Document image version override pattern
5. **[Low]** Add Makefile for common operations

## Benefits

- **Deterministic**: Alphabetical ordering is predictable
- **DRY**: Base configs reduce duplication
- **Maintainable**: Clear separation of concerns
- **Institutional Quality**: Follows enterprise GitOps best practices
