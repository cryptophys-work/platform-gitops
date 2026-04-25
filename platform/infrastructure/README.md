## Missing Components
- `scheduling/`: Node scheduling policies - sourced from cluster-specific overlays
- `networking/`: Cilium configuration - defined in cluster/talos-prod/kustomization
- Other empty dirs are populated via external tools or manual deployment

## Sourcing Information
- **Helm Charts**: Infrastructure components are primarily deployed using Helm charts managed by Flux. Sources are defined in `HelmRepository` resources.
- **Git Repositories**: Some manifests are sourced from external Git repositories via `GitRepository` resources.
- **Container Images**: Images are pulled from the internal Harbor registry at `registry.cryptophys.work`.
- **Manual Deployment**: Certain components may require manual deployment or are populated by external tools.