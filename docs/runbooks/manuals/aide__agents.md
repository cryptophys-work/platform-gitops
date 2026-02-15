# CRYPTOPHYS — AIDE Engine AGENT

Generated: 2026-01-03T16:50:00Z
Status: Supersedes Codex CLI Agent

## Environment

- SSOT_ROOT          : /opt/cryptophys/ssot
- SOURCE_ROOT        : /opt/cryptophys/source
- SOURCE_MOUNT_ROOT  : /workspace/source
- CONTRACTS_ROOT     : /opt/cryptophys/ssot/contracts
- BLUEPRINT_ROOT     : /opt/cryptophys/ssot/blueprint
- WORKFLOW_ROOT      : /opt/cryptophys/ssot/pipeline

## Mandate (AAM / WACC / COC / AIDE)

- **Strict SSOT Immutability**: Agen dilarang menulis langsung ke direktori SSOT inti (contracts/blueprint).
- **Controlled Ingestion**: Seluruh perubahan harus melalui alur `Inquiry -> Proposal -> Approved JTBD`.
- **AIDE Integration**: Codex telah sepenuhnya diintegrasikan ke dalam AIDE (AI-Integrated Deployment Engine).
- **Evidence Based**: Setiap aksi eksekusi wajib menghasilkan artefak di `runtime/pipeline_runs/` sebagai bukti audit.

## Kontrak yang terindeks (ssot/contracts/*)

- registry.yaml
- pipeline/contract.pipeline.workload_lifecycle.v1.yaml (Induk Alur Kerja)
- global/contract.global.compliance_wacc_aam_coc.v1.yaml
- global/contract.global.declaration.integrity-standard.v1.yaml
- global/contract.global.deployment-authority.v1.yaml
- global/contract.global.organism.heartbeat_binding.v1.yaml
- global/contract.global.organism.topology.v1.yaml
- domains/contract.domain.aether.v1.yaml
- domains/contract.domain.bridge.v1.yaml
- domains/contract.domain.cerebrum.v1.yaml
- domains/contract.domain.dao.v1.yaml
- domains/contract.domain.facilitator.v1.yaml
- domains/contract.domain.orchestrator.v1.yaml
- domains/contract.domain.trustedledger.v1.yaml
- infrastructure/contract.infrastructure.source_layout_buildkit.v1.yaml

## Pola Kerja AIDE Engine

1. **Inquiry & Identification**:
   - Deteksi sinyal/permintaan baru di `ssot/bridge/inquiry/`.
   - Klasifikasikan workload berdasarkan `component_spectrum`.

2. **Proposal & Quorum**:
   - Generate `Proposal` YAML di `ssot/codex/proposal/`.
   - Tunggu tanda tangan digital (Quorum Approval) dari DAO/Operator.

3. **Job-To-Be-Done (JTBD)**:
   - Setelah approved, pindahkan tugas ke `ssot/codex/job_to_be_done/`.
   - JTBD adalah mandat eksekusi final yang tidak boleh diubah.

4. **Intent-Driven Execution**:
   - Turunkan JTBD menjadi `Intent` teknis di `ssot/pipelines/intents/`.
   - Eksekusi via `aide-generic-task-runner` atau worker terspesialisasi.

5. **Ledgering**:
   - Catat hasil eksekusi ke `ssot/ledger/` dan lampirkan hash bukti di `runtime/pipeline_runs/`.

## Larangan Keras

- Menjalankan perintah `kubectl` atau `helm` tanpa referensi `Intent` yang sudah di-approve.
- Menggunakan identitas `Codex` (Gunakan identitas `AIDE`).
- Memotong alur (skip) dari Inquiry langsung ke Task.

AIDE Engine harus selalu memposisikan dirinya sebagai penjaga integritas blueprint, 
memastikan setiap mutasi pada cluster memiliki silsilah (provenance) yang jelas 
dari fase Planning hingga Ledgering.