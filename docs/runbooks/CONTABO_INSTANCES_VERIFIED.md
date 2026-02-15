# Contabo Instances - Verified Information (SSOT)

**Source:** `/opt/cryptophys/talos/` (Single Source of Truth)  
**Date:** 2026-02-14  
**Status:** VERIFIED from CLUSTER_MANIFEST.yaml and node configs

---

## VERIFIED INSTANCES (from SSOT)

### Control-Plane Nodes

#### 1. CORTEX (Control-Plane #1)
```yaml
hostname: cortex-178-18-250-39
public_ip: 178.18.250.39
subnet: /20 (255.255.240.0)
gateway: 178.18.240.1
interface: ens18
wireguard_ip: 10.8.0.2
role: controlplane
config_path: /opt/cryptophys/talos/configs/ssot/cortex/talos__cortex_cp.yaml
status: ❌ DOWN (Talos API timeout 2+ hours)
```

**Network Config (from YAML):**
```yaml
interfaces:
  - interface: ens18
    dhcp: false
    addresses:
      - 178.18.250.39/20
    routes:
      - network: 0.0.0.0/0
        gateway: 178.18.240.1
```

**GRUB Kernel Params (for reinstall):**
```
ip=178.18.250.39::178.18.240.1:255.255.240.0:cortex:ens18:off
ifname=ens18:<MAC>  # MAC unknown (need rescue mode to discover)
pti=on slab_nomerge
```

---

#### 2. CEREBRUM (Control-Plane #2)
```yaml
hostname: cerebrum-157-173-120-200
public_ip: 157.173.120.200
subnet: /20 (255.255.240.0)
gateway: 157.173.112.1
interface: ens18
wireguard_ip: 10.8.0.4
role: controlplane
config_path: /opt/cryptophys/talos/configs/ssot/cerebrum/talos__cerebrum_cp.yaml
status: ❌ DOWN (Talos API timeout)
priority: 🔥 #1 (has etcd snapshot)
```

**Network Config (from YAML):**
```yaml
interfaces:
  - interface: ens18
    dhcp: false
    addresses:
      - 157.173.120.200/20
    routes:
      - network: 0.0.0.0/0
        gateway: 157.173.112.1
```

**GRUB Kernel Params (for reinstall):**
```
ip=157.173.120.200::157.173.112.1:255.255.240.0:cerebrum:ens18:off
ifname=ens18:<MAC>  # MAC unknown (need rescue mode to discover)
pti=on slab_nomerge
```

**Etcd Snapshot Available:**
- `/tmp/cerebrum-snapshot.db` (218MB, 13,408 keys, revision 102,682,404)
- Most recent backup (taken during recovery attempt)

---

#### 3. CORPUS (Control-Plane #3)
```yaml
hostname: corpus-207-180-206-69
public_ip: 207.180.206.69
subnet: /18 (255.255.192.0)
gateway: 207.180.192.1
interface: ens18
wireguard_ip: 10.8.0.3
role: controlplane
config_path: /opt/cryptophys/talos/configs/ssot/corpus/talos__corpus_cp.yaml
status: ❌ DOWN (Talos API timeout 2+ hours)
```

**Network Config (from YAML):**
```yaml
interfaces:
  - interface: ens18
    dhcp: false
    addresses:
      - 207.180.206.69/18
    routes:
      - network: 0.0.0.0/0
        gateway: 207.180.192.1
```

**GRUB Kernel Params (for reinstall):**
```
ip=207.180.206.69::207.180.192.1:255.255.192.0:corpus:ens18:off
ifname=ens18:<MAC>  # MAC unknown (need rescue mode to discover)
pti=on slab_nomerge
```

---

### Worker Nodes

#### 4. CAMPUS (Worker #1)
```yaml
hostname: campus-173-212-221-185
public_ip: 173.212.221.185
subnet: /24 (255.255.255.0)
gateway: 173.212.221.1
interface: ens18
mac_address: 00:50:56:5f:48:b7  # ✅ VERIFIED from recovery log
wireguard_ip: 10.8.0.6
role: worker
architecture: Intel/AMD (x86_64 or aarch64)
config_path: /opt/cryptophys/talos/configs/ssot/campus/talos__campus_worker.yaml
status: ✅ HEALTHY (waiting for cluster API)
```

**GRUB Kernel Params (verified working):**
```
ip=173.212.221.185::173.212.221.1:255.255.255.0:campus:ens18:off:1.1.1.1
ifname=ens18:00:50:56:5f:48:b7
pti=on slab_nomerge
```

---

#### 5. AETHER (Worker #2)
```yaml
hostname: aether-212-47-66-101
public_ip: 212.47.66.101
subnet: /24 (255.255.255.0)
gateway: 212.47.66.1
interface: ens18
wireguard_ip: 10.8.0.5
role: worker
architecture: x86_64 (AMD64)
config_path: /opt/cryptophys/talos/configs/ssot/aether/talos__aether_worker.yaml
status: ✅ HEALTHY (waiting for cluster API)
```

---

## MISSING INFORMATION (Requires Contabo API or Rescue Mode)

### MAC Addresses (Unknown for 4/5 nodes)
```
✅ campus: 00:50:56:5f:48:b7 (verified)
❓ cortex: UNKNOWN (discover via rescue mode SSH: ip link show)
❓ cerebrum: UNKNOWN (discover via rescue mode SSH: ip link show)
❓ corpus: UNKNOWN (discover via rescue mode SSH: ip link show)
❓ aether: UNKNOWN (discover via rescue mode SSH: ip link show)
```

**How to discover MAC (once in rescue mode):**
```bash
# SSH to rescue environment
ssh root@<IP>

# Get MAC address
ip link show ens18 | grep ether | awk '{print $2}'
# OR
cat /sys/class/net/ens18/address
```

---

### Contabo Instance IDs (Unknown for all nodes)
```
❓ cortex: UNKNOWN (need API: GET /v1/compute/instances?ip=178.18.250.39)
❓ cerebrum: UNKNOWN (need API: GET /v1/compute/instances?ip=157.173.120.200)
❓ corpus: UNKNOWN (need API: GET /v1/compute/instances?ip=207.180.206.69)
❓ campus: UNKNOWN (need API: GET /v1/compute/instances?ip=173.212.221.185)
❓ aether: UNKNOWN (need API: GET /v1/compute/instances?ip=212.47.66.101)
```

**Instance IDs are REQUIRED for:**
- Triggering rescue mode (POST `/v1/compute/instances/{id}/actions/rescue`)
- Rebooting instance (POST `/v1/compute/instances/{id}/actions/restart`)
- Console access (VNC/KVM)

---

## HOW TO GET CONTABO API ACCESS

### Option 1: API Credentials (Programmatic)

**Step 1: Get OAuth2 Credentials**
1. Login to Contabo Customer Control Panel: https://my.contabo.com/
2. Navigate to: **API → Credentials**
3. Click "Create Client"
4. Save credentials:
   - `CLIENT_ID`: UUID format (e.g., `int_xxxxx`)
   - `CLIENT_SECRET`: Secret string
   - `API_USER`: Your email
   - `API_PASS`: Your password

**Step 2: Export to Environment**
```bash
export CONTABO_CLIENT_ID="int_xxxxx"
export CONTABO_CLIENT_SECRET="xxxxxxxxxx"
export CONTABO_API_USER="your-email@example.com"
export CONTABO_API_PASS="your-password"
```

**Step 3: Get Access Token**
```bash
export CONTABO_TOKEN=$(curl -s -X POST \
  "https://auth.contabo.com/auth/realms/contabo/protocol/openid-connect/token" \
  -d "client_id=$CONTABO_CLIENT_ID" \
  -d "client_secret=$CONTABO_CLIENT_SECRET" \
  -d "username=$CONTABO_API_USER" \
  -d "password=$CONTABO_API_PASS" \
  -d "grant_type=password" | jq -r .access_token)

echo "Token: $CONTABO_TOKEN"
```

**Step 4: List Instances**
```bash
curl -s -H "Authorization: Bearer $CONTABO_TOKEN" \
  -H "x-request-id: $(uuidgen)" \
  "https://api.contabo.com/v1/compute/instances?size=50" | jq .
```

**Step 5: Find Instance ID by IP**
```bash
# Example for cerebrum
curl -s -H "Authorization: Bearer $CONTABO_TOKEN" \
  -H "x-request-id: $(uuidgen)" \
  "https://api.contabo.com/v1/compute/instances?size=50" | \
  jq -r ".data[] | select(.ipConfig.v4.ip == \"157.173.120.200\") | \"ID: \(.instanceId) - \(.name)\""
```

---

### Option 2: Web Console (Manual)

**For users without API access:**

1. Login to Contabo Control Panel: https://my.contabo.com/
2. Navigate to: **Compute → Instances**
3. Find instance by IP address (e.g., 157.173.120.200)
4. Click instance → Actions → **Enable Rescue Mode**
5. Select: **Debian 12** + **SSH Key**
6. Wait 2-3 minutes for rescue mode activation
7. SSH to instance: `ssh root@<IP>`
8. Run Superior Flash installation procedure
9. Return to web panel → Actions → **Restart**

---

## NETWORK TOPOLOGY (Verified from SSOT)

### Subnet Allocation
```
cortex:    178.18.250.39/20  → Network: 178.18.240.0/20  (4096 hosts)
cerebrum:  157.173.120.200/20 → Network: 157.173.112.0/20 (4096 hosts)
corpus:    207.180.206.69/18  → Network: 207.180.192.0/18 (16384 hosts)
campus:    173.212.221.185/24 → Network: 173.212.221.0/24 (256 hosts)
aether:    212.47.66.101/24   → Network: 212.47.66.0/24   (256 hosts)
```

### Wireguard Mesh (Full Mesh Topology)
```
Bastion:   10.8.0.1 (167.86.126.209)
Cortex:    10.8.0.2 (178.18.250.39)
Corpus:    10.8.0.3 (207.180.206.69)
Cerebrum:  10.8.0.4 (157.173.120.200)
Aether:    10.8.0.5 (212.47.66.101)
Campus:    10.8.0.6 (173.212.221.185)

Port: 51821/udp (all nodes)
Topology: True Full Mesh (each node peers with all others)
```

---

## REINSTALL PRIORITY (Based on SSOT Analysis)

### Phase 1: CEREBRUM (Priority #1) 🔥
```yaml
reason: Has most recent etcd snapshot (218MB, 13K keys)
timeline: 30-60 minutes
risk: 🟢 LOW (snapshot verified, config intact)
method: Superior Flash (MBR + GZIP CPIO)
ip: 157.173.120.200
gateway: 157.173.112.1
subnet: /20
interface: ens18
mac: UNKNOWN (discover in rescue: ip link show ens18)
```

**Post-Install Actions:**
1. Bootstrap etcd: `talosctl bootstrap -n 157.173.120.200`
2. Restore snapshot: `etcdctl snapshot restore /tmp/cerebrum-snapshot.db`
3. Verify cluster: `kubectl get nodes`

---

### Phase 2: CORTEX (Priority #2) ⚠️
```yaml
reason: Rejoin after cerebrum online (or reinstall if stuck)
timeline: 30 minutes
risk: 🟢 LOW (cerebrum already providing cluster API)
method: Superior Flash
ip: 178.18.250.39
gateway: 178.18.240.1
subnet: /20
interface: ens18
mac: UNKNOWN (discover in rescue)
```

**Post-Install:**
- SKIP bootstrap (cerebrum already leader)
- Node joins etcd cluster automatically

---

### Phase 3: CORPUS (Priority #3) 🟢
```yaml
reason: Rejoin after cortex online (or reinstall if stuck)
timeline: 30 minutes
risk: 🟢 LOW (2/3 quorum already established)
method: Superior Flash
ip: 207.180.206.69
gateway: 207.180.192.1
subnet: /18
interface: ens18
mac: UNKNOWN (discover in rescue)
```

**Post-Install:**
- SKIP bootstrap
- Node joins as 3rd etcd member

---

## VERIFICATION CHECKLIST

### After Each Reinstall:

```bash
# 1. Ping test
ping -c 3 <NODE_IP>

# 2. Talos API responsive
talosctl -n <NODE_IP> version

# 3. Node appears in etcd members
talosctl -n <NODE_IP> get members

# 4. Kubernetes node Ready
kubectl get nodes

# 5. Pods scheduled
kubectl get pods -A -o wide | grep <NODE_NAME>
```

### After Full Recovery (3/3 CP):

```bash
# 1. All control-plane Ready
kubectl get nodes -l node-role.kubernetes.io/control-plane
# Expected: cerebrum, cortex, corpus - Ready

# 2. Etcd quorum healthy (3/3)
talosctl get members -n 157.173.120.200
# Expected: 3 members, 1 leader

# 3. All pods Running
kubectl get pods -A
# Expected: 0 Pending, 0 CrashLoopBackOff

# 4. Platform services restored
kubectl get pods -n argocd -n harbor -n gitea
# Expected: All Running
```

---

## REQUIRED FOR EXECUTION

### Before Starting Reinstall:

- [x] ✅ Verified IPs from SSOT (CLUSTER_MANIFEST.yaml)
- [x] ✅ Verified configs exist in `/opt/cryptophys/talos/configs/ssot/`
- [x] ✅ Etcd snapshot available (`/tmp/cerebrum-snapshot.db`)
- [ ] ⚠️ Contabo API credentials (get from control panel)
- [ ] ⚠️ Instance IDs (discover via API or web panel)
- [ ] ⚠️ MAC addresses (discover in rescue mode)
- [x] ✅ Superior Flash procedure documented (`RUNBOOK_CONTABO_SUPERIOR_FLASH.md`)

### Minimum to Proceed (Manual Method):

**Can proceed WITHOUT API if:**
1. Use Contabo web panel (manual rescue mode activation)
2. Discover MAC addresses during rescue SSH session
3. Manually reboot from web panel

**NEXT STEP:** User needs to provide either:
- **Option A:** Contabo API credentials → Automated procedure
- **Option B:** Web panel access → Manual procedure (slower but works)

---

## SUMMARY

**VERIFIED from SSOT (/opt/cryptophys/talos/):**
- ✅ All 5 node IPs confirmed
- ✅ All network configs (subnet, gateway)
- ✅ All YAML configs exist and valid
- ✅ Etcd snapshot available (cerebrum)
- ✅ Campus MAC address known (00:50:56:5f:48:b7)

**MISSING (Need Contabo API or manual discovery):**
- ❌ Contabo instance IDs (required for API)
- ❌ MAC addresses for 4 nodes (cortex, cerebrum, corpus, aether)

**CAN PROCEED with manual method (web panel) without API credentials.**  
**Automated method (API) preferred but not required.**

