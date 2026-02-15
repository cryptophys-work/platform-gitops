# Talos Cluster Single Source of Truth (SSOT)

**Project:** Cryptophys Universe - Genesis Phase
**Cluster Name:** `cryptophys-genesis`
**Last Verified:** 2026-01-17

---

## 1. Directory Architecture
Seluruh konfigurasi yang ada di sini adalah **Law**. Perubahan pada cluster HARUS dimulai dari modifikasi file di folder ini sebelum di-apply ke node.

```text
/opt/cryptophys/talos/
├── README.md                   # Dokumen ini (Peta Navigasi)
├── secrets/                    # Rahasia Cluster (Kunci CA, WG Keys)
│   ├── secrets.yaml            # Talos Cluster Secrets (CA, Tokens)
│   ├── *.wg                    # Kunci Privat Wireguard per node
│   └── secrets.yaml.bak.*	      # Backup rahasia lama (History)
├── manifests/                  # Definisi Infrastruktur
│   └── nodes.yaml              # Daftar Node, IP, Gateway, dan Metadata
└── configs/ssot/	               # Konfigurasi Mesin Final (Definitif)
    ├── talosconfig 	            # Admin Client Config
    ├── kube/config 	            # Kubernetes Admin Config
    ├── cortex/talos__cortex_cp.yaml
    ├── cerebrum/talos__cerebrum_cp.yaml
    ├── corpus/talos__corpus_cp.yaml
    ├── campus/talos__campus_worker.yaml
    └── aether/talos__aether_worker.yaml
```

Legacy (non-SSOT) configs dipindahkan ke:
`/opt/cryptophys/talos/_legacy_backup/` (arsip saja, tidak dipakai cluster).

---

## 2. Infrastructure Inventory
| Node | Role | Public IP | Wireguard IP | Netmask | Gateway |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Cortex** | LEADER | 178.18.250.39 | 10.8.0.2 | /20 | 178.18.240.1 |
| **Cerebrum** | CP | 157.173.120.200 | 10.8.0.4 | /20 | 157.173.112.1 |
| **Corpus** | CP | 207.180.206.69 | 10.8.0.3 | /18 | 207.180.192.1 |
| **Campus** | Worker | 173.212.221.185 | 10.8.0.6 | /24 | 173.212.221.1 |
| **Aether** | Worker | 212.47.66.101 | 10.8.0.5 | /21 | 212.47.64.1 |

---

## 3. Operational Protocols

### WireGuard Full Mesh (Invariant)
Setiap node WAJIB memiliki peers untuk semua node lain + bastion (tidak termasuk dirinya sendiri).
Port standar: UDP `51821`.

### Sync Configuration (Idempotency)
Untuk memastikan node sesuai dengan SSOT, jalankan:
```bash
talosctl apply-config --talosconfig configs/ssot/talosconfig \
  -n <NODE_IP> -e <NODE_IP> \
  --file configs/ssot/<NODE_NAME>/talos__<NODE_NAME>_<ROLE>.yaml
```

### Emergency Recovery (Wipe & Join)
1. Boot node ke Rescue Mode.
2. Wipe disk: `dd if=/dev/zero of=/dev/sda bs=1M count=1000`.
3. Install Kernel Maintenance.
4. Apply file dari `configs/ssot/` dengan flag `--insecure`.

### Cluster Health
```bash
# Cek Mesin
talosctl --talosconfig configs/ssot/talosconfig -n <IPs> get machinestatus
# Cek Etcd
talosctl --talosconfig configs/ssot/talosconfig -n <LEADER_IP> etcd members
# Cek K8s
KUBECONFIG=configs/ssot/kube/config kubectl get nodes
```

---

## 4. Security & Mesh
- **Firewall:** Bastion (Hub) harus mengizinkan forwarding `wg0` <-> `wg0`.
- **Wireguard:** Port UDP 51821 terbuka di Bastion. Port internal Etcd 2379/2380 berjalan di atas `wg0`.

## 5. CNI Baseline (Cilium)
- **Release:** `cilium` di `kube-system` via Helm.
- **Mode:** kube-proxy replacement = true.
- **Encryption:** WireGuard node-to-node enabled.
- **Cluster identity:** `cryptophys-genesis` (id=1) untuk korelasi audit.

```
