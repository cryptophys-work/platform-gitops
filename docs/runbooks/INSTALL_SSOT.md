# Talos Linux Installation: The Single Source of Truth (SSOT)

**Status:** CANONICAL & VERIFIED (Session 2026-01-17)
**Root Path:** `/opt/cryptophys/talos/configs/ssot/`

---

## 1. Directory Structure (The Truth)
```text
/opt/cryptophys/talos/configs/ssot/
├── talosconfig                         # Shared cluster admin config
├── kube/
│   └── config                          # Cluster Kubernetes admin config (Kubeconfig)
├── cortex/talos__cortex_cp.yaml        # LEADER (178.18.250.39)
├── cerebrum/talos__cerebrum_cp.yaml    # MEMBER (157.173.120.200)
├── corpus/talos__corpus_cp.yaml        # MEMBER (207.180.206.69)
├── campus/talos__campus_worker.yaml    # WORKER (173.212.221.185)
└── aether/talos__aether_worker.yaml    # WORKER (212.47.66.101)
```

---

## 2. Tooling Reference (Deterministic Access)

### Talosctl Configuration
Wajib menggunakan path absolut ke SSOT talosconfig (Dilarang menggunakan Symlink):
```bash
# Set alias atau gunakan flag eksplisit
alias talosctl="talosctl --talosconfig /opt/cryptophys/talos/configs/ssot/talosconfig"
```
**Peringatan:** Penggunaan symlink dilarang untuk menjaga determinisme sistem.

### Kubectl Configuration
Wajib menggunakan path absolut ke SSOT kubeconfig:
```bash
export KUBECONFIG=/opt/cryptophys/talos/configs/ssot/kube/config
```
**Perintah Penting:**
- `kubectl get nodes`: Cek status integrasi node ke Kubernetes.
- `kubectl get pods -A`: Cek kesehatan pod sistem (coredns, flannel, dll).

---

## 3. Workflow Deterministik (New Node Join)
1.  **Preparation:** Generate config di folder SSOT node.
2.  **Installation:** Wipe disk -> Install kernel via Rescue Mode.
3.  **Bootstrap (Leader Only):** Jalankan di node pertama.
4.  **Application:** `talosctl apply-config --insecure --file <SSOT_FILE>`.
5.  **Validation:**
    - Tunggu `talosctl get machinestatus` menunjukkan `stage: running`.
    - Tunggu `kubectl get nodes` menunjukkan `Ready`.

## 4. Contabo Legacy BIOS (Disk Format)
Untuk Contabo Legacy BIOS, ext4 default sering gagal boot. Gunakan format khusus:
```bash
mkfs.ext4 -O ^64bit,^metadata_csum,^extent /dev/sda1
```
Ini WAJIB untuk node bare-metal/rescue yang memakai GRUB manual.

## 4. Networking & Mesh (True Full Mesh)
- **Topologi:** Full Mesh (Direct-Peering). Setiap node bicara langsung antar IP Publik.
- **Peers:** Setiap node memiliki list peer seluruh anggota cluster + Bastion sebagai fallback.
- **Firewall (v1.12):** Menggunakan resource `NetworkRuleConfig` terpisah untuk membuka port `51821/udp` bagi seluruh IP cluster.
- **ListenPort:** Eksplisit diatur ke `51821` di MachineConfig.
- **Status:** ZERO SPOF terverifikasi.
