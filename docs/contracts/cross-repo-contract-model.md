# Cross-Repository Contract Model

## Repositories
- `platform-gitops`: platform baseline and cluster runtime infrastructure manifests.
- `apps-gitops`: application workload delivery and app-level delivery manifests.
- `ssot-core`: governance contracts, policy bundles, and shared standards.

## Ownership Boundaries
- Platform team owns cluster services/controllers/policy runtimes in `platform-gitops`.
- Application teams own app release state in `apps-gitops`.
- Governance/security owns versioned policy contracts in `ssot-core`.

## Promotion Flow
1. Contract/policy change lands in `ssot-core` with version tag.
2. `platform-gitops` updates to consume the approved contract version.
3. `apps-gitops` validates workloads against the same approved contract version.
4. Production promotion only when platform + app compatibility checks pass.

## Versioned Contract Requirements
Each contract release MUST define:
- Allowed namespaces and tenancy boundaries.
- Required labels/annotations for workloads.
- Policy exception governance rules.
- CRD/API compatibility expectations.

## Compatibility Matrix
Maintain a matrix per release cycle:
- `ssot-core` contract version
- `platform-gitops` commit/tag validated against contract
- `apps-gitops` commit/tag validated against contract
- validation date + approver

## Change Management Rules
- Breaking contract changes require major version increment.
- Non-breaking additions require minor version increment.
- Fix-only changes require patch version increment.
