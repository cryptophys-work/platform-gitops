# High Availability Architecture: Cryptophys Genesis Cluster

**Status:** CANONICAL (Verified Feb 14, 2026)
**Platform:** Contabo VPS (Multi-Subnet / Multi-Region)

## 1. The Multi-Subnet Constraint
The Control Plane nodes (`cortex`, `corpus`, `cerebrum`) reside in different public subnets:
- cortex: 178.18.250.39/20
- corpus: 207.180.206.69/18
- cerebrum: 157.173.120.200/20

**Finding:** Because these nodes do not share a single Layer 2 broadcast domain, **Layer 2 VIP solutions (like Talos Native VIP or Kube-VIP in ARP mode) are NON-VIABLE**. ARP announcements cannot cross subnet boundaries.

## 2. Current Implementation: DNS Round-Robin (Layer 3 HA)
The High Availability for the Kubernetes API is currently achieved via DNS Round-Robin using the hostname **`api.cryptophys.work`**.

### Characteristics:
- **DNS Records:** Points to all three Control Plane public IPs.
- **TLS Stability:** Secured via `certSANs` in Talos MachineConfig (all node IPs + HA hostname included).
- **Failover Latency:** Depends on client-side DNS caching and TTL (typically 5-30 seconds).

## 3. Configuration Compliance
All Control Plane nodes MUST have the following in their SSOT configuration:

```yaml
machine:
  certSANs:
    - api.cryptophys.work
    - [NODE_PUBLIC_IP]
    - [PEER_PUBLIC_IPS...]
```

## 4. Internal Workload Best Practice
Internal components (Flux, ArgoCD, Linkerd) should use the HA hostname `api.cryptophys.work` instead of direct node IPs to ensure survival during single-node outages.

## 5. Potential Future Enhancements
- **Cloudflare Load Balancer:** Use an external L7/L4 Load Balancer with active health checks to reduce failover latency to < 5 seconds.
- **Wireguard Anycast (Experimental):** Exploring Anycast over the internal Wireguard mesh (`wg0`) for Layer 3 internal VIP.
