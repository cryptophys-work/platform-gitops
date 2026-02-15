# SPIFFE CSI Driver - mTLS Configuration Guide

## Status: ✅ COMPLETE

### Infrastructure Deployed
- **SPIRE Server HA**: 3 replicas (PostgreSQL backend)
- **SPIRE Agents**: 5 DaemonSet pods (all nodes attested)
- **SPIFFE CSI Driver**: 5 DaemonSet pods (all nodes)
- **CSIDriver Object**: Registered (`csi.spiffe.io`)

### Verification Results

#### 1. CSI Driver Status
```bash
$ kubectl get daemonset -n spire-system spiffe-csi-driver
NAME                DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
spiffe-csi-driver   5         5         5       5            5

$ kubectl get pods -n spire-system -l app=spiffe-csi-driver
NAME                      READY   STATUS    RESTARTS   AGE   NODE
spiffe-csi-driver-9vmmq   2/2     Running   0          5m    cortex-178-18-250-39
spiffe-csi-driver-cqf78   2/2     Running   0          5m    campus-173-212-221-185
spiffe-csi-driver-gqdvz   2/2     Running   0          5m    cerebrum-157-173-120-200
spiffe-csi-driver-knbt5   2/2     Running   0          5m    corpus-207-180-206-69
spiffe-csi-driver-src45   2/2     Running   0          5m    aether-212-47-66-101
```

#### 2. CSI Volume Injection
Test pods deployed in `mtls-test` namespace successfully mount SPIFFE Workload API socket:

```bash
$ kubectl get pods -n mtls-test -l app=mtls-client
NAME                           READY   STATUS    RESTARTS   AGE
mtls-client-85bb7fccc5-v7sc2   1/1     Running   0          8m

$ kubectl exec -n mtls-test mtls-client-85bb7fccc5-v7sc2 -- ls -la /spiffe-workload-api/agent/
total 0
drwxr-xr-x    2 root     root            60 Feb 15 00:00 .
drwxr-xr-x    3 root     root            80 Feb 15 00:00 ..
srwxrwxrwx    1 root     root             0 Feb 15 00:00 agent.sock
```

**Socket Path**: `/spiffe-workload-api/agent/agent.sock`

### Application Configuration

#### How to Enable Automatic mTLS

**Step 1**: Add CSI volume to your Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: your-app
  namespace: your-namespace
spec:
  template:
    spec:
      containers:
      - name: app
        image: your-image:tag
        volumeMounts:
        - name: spiffe-workload-api
          mountPath: /spiffe-workload-api
          readOnly: true
      volumes:
      - name: spiffe-workload-api
        csi:
          driver: csi.spiffe.io
          readOnly: true
```

**Step 2**: Register workload identity (per node):

```bash
kubectl exec -n spire-system spire-server-0 -- \
  /opt/spire/bin/spire-server entry create \
  -parentID spiffe://cryptophys.work/spire/agent/k8s_psat/cryptophys-genesis/<node-name> \
  -spiffeID spiffe://cryptophys.work/<namespace>/<app-name> \
  -selector k8s:ns:<namespace> \
  -selector k8s:pod-label:app:<app-name> \
  -x509SVIDTTL 3600
```

**Universal Registration** (for apps that may run on any node):

```bash
for node in cerebrum-157-173-120-200 corpus-207-180-206-69 cortex-178-18-250-39 aether-212-47-66-101 campus-173-212-221-185; do
  kubectl exec -n spire-system spire-server-0 -- \
    /opt/spire/bin/spire-server entry create \
    -parentID spiffe://cryptophys.work/spire/agent/k8s_psat/cryptophys-genesis/$node \
    -spiffeID spiffe://cryptophys.work/<namespace>/<app-name> \
    -selector k8s:ns:<namespace> \
    -selector k8s:pod-label:app:<app-name> \
    -x509SVIDTTL 3600
done
```

**Step 3**: Use SPIFFE SDK in your application:

```go
// Go example using go-spiffe
package main

import (
    "context"
    "github.com/spiffe/go-spiffe/v2/workloadapi"
)

func main() {
    ctx := context.Background()
    
    // Workload API socket mounted by CSI driver
    source, err := workloadapi.NewX509Source(
        ctx,
        workloadapi.WithClientOptions(
            workloadapi.WithAddr("unix:///spiffe-workload-api/agent/agent.sock"),
        ),
    )
    if err != nil {
        panic(err)
    }
    defer source.Close()
    
    // Get X.509-SVID
    svid, err := source.GetX509SVID()
    if err != nil {
        panic(err)
    }
    
    // Use svid.Certificates and svid.PrivateKey for mTLS
}
```

### Workload Registrations Created

Current test workload entries (10 total):

- **Backend**: `spiffe://cryptophys.work/mtls-test/backend` (5 entries, one per node)
- **Client**: `spiffe://cryptophys.work/mtls-test/client` (5 entries, one per node)

View all entries:
```bash
kubectl exec -n spire-system spire-server-0 -- \
  /opt/spire/bin/spire-server entry show -selector k8s:ns:mtls-test
```

### Production Deployment Sequence

**For platform services (Gitea, Harbor, ArgoCD, MinIO, Velero):**

1. Add CSI volume to Helm `values.yaml`:
   ```yaml
   extraVolumes:
     - name: spiffe-workload-api
       csi:
         driver: csi.spiffe.io
         readOnly: true
   extraVolumeMounts:
     - name: spiffe-workload-api
       mountPath: /spiffe-workload-api
       readOnly: true
   ```

2. Register workload identities (before deployment)
3. Deploy service
4. Verify identity issuance (logs or `/healthz` endpoint)

### Cilium Integration (Optional)

**Current State**: Cilium requesting Delegated Identity API (not yet configured)

**Error observed**:
```
Permission denied; caller not configured as an authorized delegate
```

**To Enable**:
1. Update SPIRE Agent config with `authorized_delegates`
2. Grant Cilium permission to issue identities on behalf of workloads
3. Enable transparent mTLS in Cilium

**Priority**: LOW (applications can use Workload API directly via CSI)

### Key Files

- `/opt/cryptophys/spiffe-csi-driver.yaml` - CSI Driver DaemonSet
- `/opt/cryptophys/mtls-verification-complete.yaml` - Test workload manifests
- `/opt/cryptophys/SPIRE_HA_FINAL_REPORT.md` - Complete SPIRE HA deployment docs

### Next Steps

✅ **SPIRE HA & CSI Driver Deployment: COMPLETE**

**Ready for Phase 2**:
1. Deploy GitOps stack (Gitea, Flux, ArgoCD) with CSI-injected identities
2. Deploy Vault with SPIFFE authentication
3. Deploy Kyverno + Gatekeeper (audit mode)
4. Deploy Observability (Prometheus, Loki, OTEL, Trivy, Headlamp)

All future workloads should follow the CSI volume pattern documented above.

---
**Report Generated**: 2026-02-15 00:23 UTC  
**Cluster**: cryptophys-genesis (5 nodes)  
**SPIRE Version**: 1.10.3  
**CSI Driver Version**: 0.2.6
