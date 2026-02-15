# Copilot instructions for cryptophys monorepo

Overview

- Monorepo with mixed ecosystems: Go, Rust, Python, Node, Docker/Helm-based services and a canonical Single Source of Truth (SSOT).
- SSOT root (read-only): /opt/cryptophys/ssot
- Primary editable source tree: /opt/cryptophys/source (working area in some environments: /workspace/source)

1) Build, test, and lint commands (per ecosystem / examples)

- Make (source/omega):
  - Build all: make build (see source/omega/Makefile)
  - Test: make test
  - Single/test binary: cd source/omega/core_go && make build; run or test specific packages with go tools below

- Go (per module):
  - Build all: go build ./...
  - Run all tests: go test ./...
  - Run a single test: go test ./path/to/package -run '^TestName$' (use regex; anchor exact name with ^ and $)
  - Build single package: go build ./path/to/package

- Rust (per Cargo.toml):
  - Build: cargo build --manifest-path path/to/Cargo.toml
  - Test: cargo test --manifest-path path/to/Cargo.toml
  - Single test: cargo test test_name --manifest-path path/to/Cargo.toml

- Python (many small services use requirements.txt):
  - Install deps: python3 -m pip install -r path/requirements.txt
  - Run guardrail lint (repo workflow): python3 tools/ssot_guardrail_lint.py .
  - Proof-of-SSOT (used by CI): python3 tools/ssot_proof_of_ssot.py --root /opt/cryptophys/ssot --report /tmp/report.json
  - Run tests (if pytest present): pytest path/to/test_file.py::test_name

- Node (per-package):
  - Install: cd path/to/package && npm install
  - Run tests: npm test (or the package-specific command)
  - Single test (jest/mocha): npm test -- -t "Test name" or use the test runner flags defined in package.json

- Docker / Helm / CI
  - AIDE components are built by actions using docker/build-push-action; local builds use docker build -t <tag> -f <Dockerfile> <context>
  - Helm deploy (examples in source/omega/Makefile): helm upgrade --install <release> <chart> --namespace <ns>

Notes on running a single test: use each ecosystem's test runner flags (go -run, cargo test <name>, pytest::testname, npm test runner flags) and run from the module/package directory so module-relative imports resolve.

2) High-level architecture (big picture)

- Purpose: cryptophys is an infrastructure-and-application monorepo that manages cluster SSOT (contracts + blueprints), runtime engines (aether/v8, omega-core), platform services (bridge, orchestrator, aide), and deployment tooling.
- Two authoritative areas:
  - SSOT (/opt/cryptophys/ssot): manifests, contracts, and blueprints; treated as authoritative/read-only for most development workflows.
  - SOURCE (/opt/cryptophys/source): editable application/service code, container/helm artifacts, and tooling for producing changes that align with SSOT.
- Multi-language service structure:
  - Rust crates (crates/*, many engine/rust-core modules)
  - Go modules (several go-runtime directories and source/omega/*)
  - Python services and tooling (many requirements.txt under source/*)
  - Node packages for select components (example: source/omega/core_js)
- CI checks in source/.github/workflows enforce SSOT proofs and guardrail linting before merges; some builds push Docker images (AIDE workflows).

3) Key repository conventions and non-obvious patterns

- SSOT is authoritative: do NOT write directly to /opt/cryptophys/ssot. Work in /workspace/source or /opt/cryptophys/source and produce changes that conform to SSOT contracts and blueprints.
- Codex/Codex-agent conventions (summarized from source/AGENTS.md):
  - Environment variables used by tooling: SSOT_ROOT (/opt/cryptophys/ssot), SOURCE_ROOT (/opt/cryptophys/source), SOURCE_MOUNT_ROOT (/workspace/source).
  - Important operations (audit, guardrail, memory logging) use codex_cli_stack and tools under tools/*; record important actions with the memory-append/guardrail-refresh commands where appropriate.
  - Microk8s/helm usage is operator-controlled; do not run environment-modifying commands unless authorized.
- CI integration:
  - Proof-of-SSOT and guardrail lint are enforced in CI (see source/.github/workflows/*.yml). These scripts expect SSOT to live at /opt/cryptophys/ssot when present; CI will skip checks if SSOT is absent.
- Multi-language tests and builds: prefer running tests inside the specific module directory to avoid cross-module path issues; use --manifest-path for cargo and module paths for go.
- Minimal-impact edits: many files are infrastructure-critical; follow the repository's EXECUTION_PLAN.md and ledgering rules before changing infra manifests.

4) Where to look next (quick pointers)

- SSOT contracts and blueprints: /opt/cryptophys/ssot/contracts and /opt/cryptophys/ssot/blueprint
- CI lint and proof scripts: source/tools/ssot_guardrail_lint.py and source/tools/ssot_proof_of_ssot.py
- Build makefiles: source/omega/Makefile and source/omega/core_go/Makefile
- AIDE build workflows: source/.github/workflows/aide_build.yml
- Agent/operator guidance: source/AGENTS.md and ssot/system/_migrated_root_*/AGENTS.md

5) Other assistant configs found and incorporated

6) DNS and CoreDNS best-practices (enterprise / telco-grade)

- Summary: For world-class institutional clusters (telco-grade / Nokia NESC/NSC), prefer a layered DNS architecture:
  - Node-local caching (node-local-dns) on every node to serve low-latency queries and reduce CoreDNS load.
  - CoreDNS in HA, with monitored forwarding to enterprise resolvers or node-local caches.
  - Enterprise resolvers behind hardened egress/NAT and monitored with DoT/DoH where possible.
- Key references: Kubernetes CoreDNS docs, CoreDNS tuning guides, NIST SP 800-81r3 for enterprise DNS guidelines, and vendor best-practices (Nokia/Infoblox). Ensure ConfigMap Corefile uses `forward`, `cache`, and `prometheus` plugins and that upstreams are reachable from all nodes.


- source/AGENTS.md (Codex/Codex-agent rules and SSOT mandates) — key rules are summarized above.
- ssot/.../AGENTS.md — migrated agent guidance included via SSOT sections.

MCP servers

- Would you like to configure any MCP servers relevant to this project (for example: cryptophys-mcp-http or other test/automation servers)?

Summary

- Created .github/copilot-instructions.md with build/test/lint commands, high-level architecture, and repository-specific conventions. Reply if you want additional sections (examples per-service, expanded test/run recipes, or coverage for a particular subproject).
