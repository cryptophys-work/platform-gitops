# GEMINI CRITICAL MEMORY - GENESIS PHASE 2026

## STATUS: PRODUCTION STABLE (Verified 2026-02-14)
- **Operational Protocol:** **SKILLS-FIRST**. Default to activating specialized skills and sub-agents. **Always inspect and verify system state before recommending or executing actions.**
- **Cluster:** `cryptophys-genesis` (5 Nodes: 3 CP, 2 Workers).
- **Health:** **100% GREEN**. All nodes Ready. All critical pods Running.
- **Recovery:** Successfully recovered `campus` and `cortex` via "Superior Flash" method.

## INFRASTRUCTURE Ground Truth
- **Nodes:**
  - `cortex` (CP): Ready. Fixed via Factory Image v1.12.0 + ISCSI Tools.
  - `campus` (Worker): Ready. Fixed via MBR/ext4 + GZIP Config.
  - `cerebrum`, `corpus`, `aether`: Ready.
- **Storage:** Longhorn v1.6.2 Running. ISCSI enabled on all nodes.
- **Networking:** Cilium Running. Wireguard Mesh Stable.
- **Apps:** Gitea, Harbor, ArgoCD, Linkerd active.
- **Security:** Kyverno active (webhooks cleaned/refreshed). Falco suspended (driver compatibility).

## RECOVERY PROTOCOL (Updates)
- **Cortex Fix:** Requires `ghcr.io/siderolabs/iscsi-tools` extension for Longhorn.
- **Campus Fix:** Requires `gzip` compressed CPIO for legacy GRUB compatibility.
- **Runbook:** Canonical procedures documented in `RUNBOOK_CONTABO_SUPERIOR_FLASH.md`.

## KYVERNO HARDENING (2026-01-31)
- **Exclusions:** kube-system, longhorn-system, platform-gitops, backup, cert-manager, ingress, crossplane-system.
- **FailurePolicy:** Ignore (Fail-Open) to prevent cluster deadlocks.
- **Status:** Webhook Configuration Patched & Values Updated.
