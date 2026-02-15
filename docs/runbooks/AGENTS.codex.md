# CRYPTOPHYS — Codex Shared Memory

- Context ID   : cryptophys-universe
- Generated at : 2025-12-05 09:22:54 +0000
- SSOT root    : /opt/cryptophys/ssot
- State file   : /opt/cryptophys/ssot/cerebrum/analysis/cerebrum.codex.memory.state.json

## 1. SSOT blueprint/index.yaml (head)
components:
  - id: cryptophys-debug-agent
    path: components/cryptophys-debug-agent.yaml
    class: reflex
    required: true

## 2. cluster.state.json (head)
{
  "timestamp": "2025-12-02T07:09:35.498596Z",
  "node": "cerebrum-reflex-6c54847497-whpvl",
  "system": {
    "cpu": 100.0,
    "ram": 42.7,
    "disk": 64.6
  },
  "namespaces": {
    "bridge": {
      "pods": [],
      "services": [
        {
          "name": "bridge-builder-service",
          "type": "ClusterIP",
          "clusterIP": "10.152.183.60",
          "ports": [
            8080
          ]
        },
        {
          "name": "bridge-core-service",
          "type": "ClusterIP",
          "clusterIP": "10.152.183.87",
          "ports": [
            8080
          ]
        },
        {
          "name": "bridge-logger-service",
          "type": "ClusterIP",
          "clusterIP": "10.152.183.195",
          "ports": [
            8080
          ]
        },
        {
          "name": "bridge-openapi-service",
          "type": "ClusterIP",
          "clusterIP": "10.152.183.144",
          "ports": [
            8080
          ]
        },
        {
          "name": "bridge-proxy-service",
          "type": "ClusterIP",
          "clusterIP": "10.152.183.84",
          "ports": [
            8080
          ]
        },
        {
          "name": "bridge-watcher-service",
          "type": "ClusterIP",
          "clusterIP": "10.152.183.33",
          "ports": [
            8080
          ]
        }
      ],
      "deployments": [
        {
          "name": "bridge-builder",
          "desired": 0,
          "available": 0,
          "conditions": [
            {
              "type": "Available",
              "status": "True",
              "reason": "MinimumReplicasAvailable"
            },
            {
              "type": "Progressing",
              "status": "True",
              "reason": "NewReplicaSetAvailable"
            }
          ]
        },
        {

## 3. cerebrum/cognition/deployment.intent.yaml (head)
version: v1.0.0
intent: full_stack_activation
requested_by: cerebrum-internal
target:
  - cerebrum
  - facilitator
  - cerebrum-llm  # replaces deprecated tiny-llm
  - builder
  - dao

status: pending
blocking_reasons:
  - missing_dao_approval
  - missing_operator_signature

## 4. Contracts snapshot ($SSOT_ROOT/contracts)

### $(realpath --relative-to="/opt/cryptophys/ssot" "$f")
```
