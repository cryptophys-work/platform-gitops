# CANONICAL RUNBOOK: Talos on Contabo (Superior Flash Method)

**Status:** PRODUCTION VERIFIED (2026-02-14)
**Scope:** Contabo VPS (Legacy BIOS/MBR)
**Method:** Manual Ext4/MBR + Maintenance Mode Boot
**Tools:** `curl` (API), `ssh`, `talosctl`

---

## 1. Contabo API Reference

### A. Authentication (Get Token)
Required for all subsequent API calls.
```bash
export CLIENT_ID="[YOUR_CLIENT_ID]"
export CLIENT_SECRET="[YOUR_CLIENT_SECRET]"
export API_USER="[YOUR_EMAIL]"
export API_PASS="[YOUR_PASSWORD]"

export CONTABO_TOKEN=$(curl -s -X POST "https://auth.contabo.com/auth/realms/contabo/protocol/openid-connect/token" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "username=$API_USER" \
  -d "password=$API_PASS" \
  -d "grant_type=password" | jq -r .access_token)
```

### B. Discovery
**1. Find Instance ID**
```bash
export TARGET_IP="178.18.250.39" # Replace with target
curl -s -H "Authorization: Bearer $CONTABO_TOKEN" \
  -H "x-request-id: $(uuidgen)" \
  "https://api.contabo.com/v1/compute/instances?size=50" \
  | jq -r ".data[] | select(.ipConfig.v4.ip == \"$TARGET_IP\") | \"ID: \(.instanceId) - \(.name)\""
```

### C. Trigger Rescue Mode
Forces the node into Debian 12 Live Rescue.
```bash
export INSTANCE_ID="202990114" # Replace with actual ID
export SSH_KEY_ID="256739"     # Replace with actual ID (from secrets)

curl -s -X POST "https://api.contabo.com/v1/compute/instances/$INSTANCE_ID/actions/rescue" \
  -H "Authorization: Bearer $CONTABO_TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-request-id: $(uuidgen)" \
  -d '{
    "rescueImage": "debian-12",
    "sshKeys": ['$SSH_KEY_ID']
  }' | jq .
```

---

## 2. The "Superior Flash" Procedure (Proven Maintenance Strategy)

**Prerequisites:**
- Node is in Rescue Mode (Debian 12).
- SSH Access is confirmed.
- MAC Address of interface (`ens18`) retrieved via `ip link show`.
- Valid Gateway IP confirmed from SSOT MachineConfig.

### Step 1: Remote Installation Execution
Execute the following block via SSH (`ssh root@$TARGET_IP`) to perform the installation.

```bash
# --- 1. Environment Prep ---
echo ">>> Setting up Environment..."
echo 'nameserver 8.8.8.8' > /etc/resolv.conf
apt-get update -qq && apt-get install -y -qq grub-pc wget

# --- 2. Partitioning (MBR/ext4) ---
echo ">>> Partitioning /dev/sda..."
wipefs -a /dev/sda
# Create MBR (o), New Primary (n, p, 1), Active (a), Write (w)
echo -e 'o\nn\np\n1\n\n\na\nw' | fdisk /dev/sda
partprobe /dev/sda
mkfs.ext4 -F /dev/sda1

# --- 3. Mount & Prepare ---
echo ">>> Mounting..."
mount /dev/sda1 /mnt
mkdir -p /mnt/boot/talos /mnt/boot/grub

# --- 4. Download Assets (v1.12.0) ---
echo ">>> Downloading Talos v1.12.0..."
cd /mnt/boot/talos
wget -qO vmlinuz https://github.com/siderolabs/talos/releases/download/v1.12.0/vmlinuz-amd64
wget -qO initramfs.xz https://github.com/siderolabs/talos/releases/download/v1.12.0/initramfs-amd64.xz

# --- 5. Install Bootloader ---
echo ">>> Installing GRUB..."
grub-install --boot-directory=/mnt/boot /dev/sda

# --- 6. Configure GRUB (Maintenance Mode) ---
# Format: ip=IP::GW:MASK:HOSTNAME:IFACE:off:DNS
cat > /mnt/boot/grub/grub.cfg <<GRUB
set default=0
set timeout=3
insmod gzio
insmod part_msdos
insmod ext2

menuentry 'Talos Linux v1.12.0 (Maintenance)' {
    set root='(hd0,msdos1)'
    linux /boot/talos/vmlinuz talos.platform=metal ifname=ens18:[MAC_ADDR] ip=[IP]::[GW]:255.255.240.0:[HOSTNAME]:ens18:off:1.1.1.1 pti=on slab_nomerge console=ttyS0 console=tty0
    initrd /boot/talos/initramfs.xz
}
GRUB

# --- 7. Finalize ---
echo ">>> Syncing & Unmounting..."
cd /
sync
umount /mnt
```

### Step 2: Reboot & Apply Config
1.  Trigger hard reboot via Contabo API (Restart action).
2.  Wait for Talos API port 50000 to open.
3.  Apply SSOT Config:
    ```bash
    talosctl apply-config --insecure -n $IP -e $IP --file talos/configs/ssot/$NODE/talos__$NODE_cp.yaml
    ```

---

## 3. Post-Installation Verification

### A. Monitor Boot
Wait for port 50000 (Talos API) to open.
```bash
until nc -z -v -w 2 $TARGET_IP 50000; do echo "Waiting..."; sleep 5; done
```

### B. Bootstrap (Leader Only)
Only for the *first* Control Plane node in a fresh cluster.
```bash
talosctl -n $TARGET_IP bootstrap
```

---

## 4. Troubleshooting Checklist

| Issue | Cause | Fix |
| :--- | :--- | :--- |
| **Boot Loop** | Incompatible Config Injection. | Use Maintenance Mode (no `talos.config` in GRUB). Apply config later. |
| **Network Unreachable** | Wrong Interface or Gateway. | Confirm Interface MAC and Gateway from SSOT. Use `ifname=` in GRUB. |
| **"Connection Refused"** | API not ready or firewall. | Ensure port 50000 is open. Use `--insecure` for first apply if PKI is new. |
| **`grub-install` missing** | Debian Rescue minimal. | Run `apt-get update && apt-get install grub-pc`. Fix DNS first! |
