# External Secrets Operator (ESO) Monitoring Implementation

## Overview
Complete ESO monitoring implementation with comprehensive alerts, ServiceMonitors, and Grafana dashboards for full observability of secret management.

## Components Added

### 1. Prometheus Alerts (`prometheus-rules.yaml`)
- **ExternalSecretsNotReady**: Critical alert when ExternalSecrets are not ready
- **ExternalSecretsSyncErrors**: Warning for sync errors
- **ClusterExternalSecretsNotReady**: Critical alert for cluster-scoped secrets
- **SecretStoresNotReady**: Critical alert when SecretStores fail
- **VaultAPIErrors**: Warning for high Vault API error rates (>10%)

### 2. ServiceMonitors (`servicemonitor-external-secrets.yaml`)
- **external-secrets**: Main ESO controller metrics
- **external-secrets-webhook**: Webhook component metrics
- **external-secrets-cert-controller**: Certificate controller metrics
- All configured with proper labels for Prometheus discovery

### 3. Existing Grafana Dashboard
- **External Secrets Operator - Secret Management** dashboard already exists
- Provides real-time monitoring of ESO health, sync rates, and error conditions

## Metrics Monitored
- `externalsecret_status_condition`: Ready state of ExternalSecrets
- `externalsecret_sync_calls_total/error`: Sync operation counts and errors
- `clusterexternalsecret_status_condition`: ClusterExternalSecret health
- `secretstore_status_condition`: SecretStore connectivity
- `externalsecret_provider_api_calls_count`: Provider API call metrics

## Alert Severity Levels
- **Critical**: System-breaking issues (ESO not ready, SecretStores down)
- **Warning**: Degraded performance (sync errors, API failures)

## Dependencies
- ESO Helm chart with `serviceMonitor.enabled: true`
- Prometheus with `release: platform-observability-prometheus` label selector