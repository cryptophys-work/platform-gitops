# CRYPTOPHYS — Codex CLI AGENT

Generated: 2025-12-05T16:18:51Z

## Environment

- SSOT_ROOT          : /opt/cryptophys/ssot
- SOURCE_ROOT        : /opt/cryptophys/source
- SOURCE_MOUNT_ROOT  : /workspace/source
- CONTRACTS_ROOT     : /opt/cryptophys/ssot/contracts
- BLUEPRINT_ROOT     : /opt/cryptophys/ssot/blueprint

## Mandate (AAM / WACC / COC)

- Tidak boleh menulis langsung ke SSOT.
- Semua perubahan kode/manifest hanya di SOURCE_MOUNT_ROOT.
- Gunakan microk8s/helm hanya atas perintah operator.
- Setiap tugas penting harus dicatat ke virtual memory via `codex_cli_stack`:
  - health
  - memory-get
  - memory-append
  - guardrail-refresh

## Kontrak yang terindeks (ssot/contracts/*)

- registry.yaml
- global/contract.global.compliance_wacc_aam_coc.v1.yaml
- global/contract.global.declaration.integrity-standard.addendum-axioms.v1.yaml
- global/contract.global.declaration.integrity-standard.addendum-resources.v1.yaml
- global/contract.global.declaration.integrity-standard.v1.yaml
- global/contract.global.deployment-authority.v1.yaml
- global/contract.global.environment_stack.v1.yaml
- global/contract.global.naming_standards.v1.yaml
- global/contract.global.organism.heartbeat_binding.v1.yaml
- global/contract.global.organism.lifecycle.v1.yaml
- global/contract.global.organism.nodes.v1.yaml
- global/contract.global.organism.topology.v1.yaml
- global/contract.global.system_architecture.v1.yaml
- storage/contract.storage.ssot-layout.v1.yaml
- domains/contract.domain.aether.v1.yaml
- domains/contract.domain.bridge.v1.yaml
- domains/contract.domain.cerebrum.v1.yaml
- domains/contract.domain.chainflow-audit.v1.yaml
- domains/contract.domain.codex.v1.yaml
- domains/contract.domain.corpus.v1.yaml
- domains/contract.domain.dao.v1.yaml
- domains/contract.domain.facilitator.v1.yaml
- domains/contract.domain.logger.v1.yaml
- domains/contract.domain.orchestrator.v1.yaml
- domains/contract.domain.storage.v1.yaml
- domains/contract.domain.trust-ledger.v1.yaml
- domains/contract.domain.watcher.v1.yaml
- infrastructure/contract.infrastructure.storage_nfs_ssot.v1.yaml
- runtime/contract.runtime.heartbeat_cerebrum-core.v1.yaml

## Blueprint yang terindeks (ssot/blueprint/*)

- 00_master_blueprint.yaml
- 01_ssot_intent.yaml
- 02_trust_ledger_blueprint.yaml
- 03_domain_map.yaml
- 04_action_scheme_registry.yaml
- index.yaml
- phase4_multicloud_multinode.yaml
- trust_chain.yaml
- components/cryptophys-debug-agent.yaml

## Pola kerja untuk Codex

1. Sebelum audit kontrak/blueprint besar:
   - Jalankan (di dalam container):
     - `python3 /workspace/tools/codex_cli_stack.py guardrail-refresh --max-files 100`

2. Setelah melakukan tugas penting (mis. update helm, audit security, dsb.):
   - Catat ke virtual memory:
     - `python3 /workspace/tools/codex_cli_stack.py memory-append          --summary "<ringkasan>"          --scope "<bridge|cerebrum|ssot/contracts|...>"          --tag "<tag-singkat>"`

3. Untuk deployment:
   - Gunakan:
     - `microk8s kubectl ...`
     - `microk8s helm3 ...`
   - Selalu ikuti kontrak & blueprint dari SSOT (read-only).

4. Dilarang:
   - Menulis ke /opt/cryptophys/ssot secara langsung.
   - Mengubah kontrak tanpa instruksi eksplisit operator.
   - Membuat resource K8s/Helm di luar niat SSOT.

## Direktori kerja utama

- Direktori kerja utama untuk operasi git/helm/python:
  - `/workspace/source`

Codex harus selalu menganggap file di SSOT sebagai hukum tertinggi (law of state),
dan file di source sebagai artefak yang boleh dimodifikasi untuk mencapai
kesesuaian dengan blueprint & kontrak.
