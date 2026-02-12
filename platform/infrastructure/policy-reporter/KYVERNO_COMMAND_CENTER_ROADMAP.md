# Kyverno Command Center (NESC-grade) Roadmap

## Current State (Implemented)

- Baseline stack is live via Flux: `policy-reporter` + `policy-reporter-ui` + `policy-reporter-kyverno-plugin`.
- UI host: `https://kyverno.cryptophys.work` (basic-auth protected).
- Policy data source is active (PolicyReports + Kyverno Event block reports).
- UX stays on upstream `policy-reporter-ui` for stability.

## Product Direction

Target product is a forked UI: **Kyverno Command Center**, with:

- Left nav: Mission Control, Policies, Workloads, Admissions, Reports, Settings
- Top bar: global search, cluster selector, tenant selector, time range
- High-density operational tables, cross-filter charts, evidence export
- Multi-cluster rollup and tenant-scoped RBAC

Alternative path: **Headlamp plugin integration** to reuse mature Kubernetes UX shell and avoid duplicating navigation/state management.

## Delivery Plan

### Sprint 0 (Control Group) — done

- Keep upstream Policy Reporter stack as known-good baseline.
- Validate data path end-to-end:
  - Kyverno -> PolicyReport CRD -> Policy Reporter API -> UI.

### Sprint 1 (UI Foundation)

- Fork `kyverno/policy-reporter-ui` to internal repo `cryptophys.adm/kyverno-command-center`.
- Implement NESC theme tokens (dark-first), compact layout primitives, table density controls.
- Build Mission Control page:
  - KPI tiles (violations, enforce blocks, top failing policy/workload)
  - trend chart + policy/category breakdown
  - chart click-to-filter.
- Add query-state share links and saved view model (local storage first).

### Sprint 1b (Headlamp Plugin POC)

- Build `headlamp-kyverno-command-center` plugin:
  - pages: Overview, Policies, Findings, Admissions
  - data source: Kubernetes API (`policyreports`, `clusterpolicyreports`, `clusterpolicies`)
  - same filters/query grammar used by operations team.
- Validate RBAC-scoped rendering per namespace/tenant profile.

### Sprint 2 (Operational Depth)

- Admissions timeline (enforce-mode blocked requests).
- Policy Portfolio page (coverage map + regression detector).
- Workload drilldown (resource detail + remediation hints + JSON export).
- Multi-cluster rollup service (read-only aggregator) if upstream API is insufficient.

## Acceptance Criteria

- KPI -> policy -> resource drilldown in <= 3 clicks.
- Multi-cluster rollup supports >= 3 clusters with stable filtering latency.
- Tenant scoping enforced: tenant A cannot read tenant B datasets.
- JSON export works for single finding and filtered result sets.

## GitOps Integration Contract

- Platform repo (`cryptophys-platform-gitops`) keeps runtime manifests only.
- App code repo (`kyverno-command-center`) owns UI and image build.
- Deployment migration:
  1. Deploy `kyverno-command-center` with parallel host (e.g. `kyverno-cc.cryptophys.work`).
  2. Validate feature parity + performance.
  3. Cut over `kyverno.cryptophys.work`.
