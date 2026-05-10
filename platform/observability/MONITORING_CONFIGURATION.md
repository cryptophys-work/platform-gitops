# Observability & Monitoring Configuration

**Status**: Production-ready ✅  
**Last Updated**: 2026-02-16  
**Components**: Grafana, Prometheus, Alertmanager, Flux Metrics

## Overview

This directory contains the monitoring and observability configuration for the cryptophys-genesis cluster.

## Components

### 1. Flux GitOps Monitoring

**Location**: `flux-monitoring/`

- **ServiceMonitors**: 6 Flux controllers (helm, kustomize, source, notification, image-automation, image-reflector)
- **Services**: Metrics endpoints for Flux controllers (port 8080)
- **Metrics**: `gotk_reconcile_*` (duration, condition, rate)

**Resources Monitored**:
- 29 Kustomizations
- 21 HelmReleases
- 6 Flux Controllers

**Apply**:
```bash
kubectl apply -f flux-monitoring/flux-servicemonitors.yaml
kubectl apply -f flux-monitoring/flux-services.yaml
kubectl apply -f flux-monitoring/flux-core-services.yaml
```

### 2. Grafana Dashboards

**Location**: `grafana-dashboards/`

#### Flux GitOps Toolkit Dashboard
- **File**: `flux-gitops-toolkit.json`
- **Panels**: 12 (stats, time series, pie charts)
- **Features**:
  - Total Kustomizations & HelmReleases
  - Reconciliation rate & duration (p95)
  - Controller health status (6/6 UP)
  - Top 10 slowest reconciliations
  - Distribution by namespace

#### Kubernetes Cluster Monitoring Dashboard
- **File**: `kubernetes-cluster-monitoring.json`
- **Panels**: 10 (stats, time series)
- **Features**:
  - Node count, pod count, namespace count
  - CPU & memory usage by node
  - Network I/O by node
  - Pods by namespace
  - Container restart monitoring

**Import to Grafana**:
```bash
# Via API
GRAFANA_POD=$(kubectl -n observability-system get pod -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n observability-system $GRAFANA_POD -- curl -X POST \
  -H "Content-Type: application/json" \
  -u "admin:password" \
  -d @/path/to/dashboard.json \
  http://localhost:3000/api/dashboards/db
```

## Datasources

**Configured in Grafana**:
1. **Prometheus** (default)
   - URL: `http://platform-observability-pro-prometheus:9090`
   - Scraping: 38 targets (32 core + 6 Flux)

2. **Alertmanager**
   - URL: `http://platform-observability-pro-alertmanager:9093`
   - Type: Prometheus Alertmanager

## Metrics Available

### Kubernetes Metrics
- `kube_node_info` - Node information
- `kube_pod_info` - Pod information
- `kube_pod_status_phase` - Pod status
- `container_cpu_usage_seconds_total` - CPU usage
- `container_memory_working_set_bytes` - Memory usage
- `container_network_*` - Network metrics

### Flux Metrics
- `gotk_reconcile_duration_seconds` - Reconciliation duration (histogram)
- `gotk_reconcile_condition` - Resource ready status
- `up{namespace="flux-system"}` - Controller health

## Access

**Grafana UI**: https://monitor.cryptophys.work  
**Credentials**: admin / CryptoGrafana2026
**Total Dashboards**: 29

## Recovery

If cluster is rebuilt:
1. Apply Flux ServiceMonitors & Services
2. Wait for Prometheus to discover targets (30s)
3. Import Grafana dashboards via API
4. Verify datasources are configured

## Maintenance

- **ServiceMonitor label requirement**: `release: platform-observability-prometheus`
- **Scrape interval**: 30 seconds
- **Dashboard refresh**: 30 seconds
- **Retention**: Prometheus default (15 days)

## Notes

- GitRepository metrics currently unavailable (source-controller not scraped yet)
- Flux controllers are HA: image-automation (2x), image-reflector (2x)
- Kube-proxy and kube-controller-manager metrics unavailable (Talos/Cilium design)
