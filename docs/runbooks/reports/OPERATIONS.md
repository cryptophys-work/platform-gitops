# Talos Cluster Operations Runbook

## Core Principle
Folder `/opt/cryptophys/talos/` adalah Single Source of Truth (SSOT). **Dilarang keras** melakukan perubahan konfigurasi langsung pada node (`talosctl edit`) tanpa memperbarui file yang bersangkutan di SSOT terlebih dahulu.

## Common Tasks

### 1. Update Configuration (Non-Destructive)
1. Modifikasi file di `/opt/cryptophys/talos/configs/ssot/<node>/`.
2. Jalankan (gunakan nama file kanonik, format `talos__<node>_<role>.yaml`):
   ```bash
   talosctl apply-config --talosconfig /opt/cryptophys/talos/configs/ssot/talosconfig \
     -n <IP> -e <IP> --file /opt/cryptophys/talos/configs/ssot/<node>/<file>.yaml
   ```

### 2. Verify Mesh Connectivity
Jika node tidak bisa sinkron etcd, periksa rute Wireguard di Bastion:
```bash
wg show
iptables -L FORWARD -n -v | grep wg0
```

### 3. Check All Logs
Untuk audit massal log error:
```bash
talosctl --talosconfig /opt/cryptophys/talos/configs/ssot/talosconfig \
  -n 178.18.250.39,157.173.120.200,207.180.206.69,173.212.221.185,212.47.66.101 \
  dmesg | grep -iE "error|fail|panic"
```

## Maintenance Procedure
Setiap kali menambahkan node baru, ikuti instruksi di `/opt/cryptophys/talos/README.md`.
