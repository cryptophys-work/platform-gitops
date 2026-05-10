# Redis HA Security Hardening

## Overview
This document describes the security hardening measures applied to the Redis HA deployment in the `apps-system` namespace.

## ServiceAccount Hardening
To minimize the attack surface of the Redis HA components, the following hardening measures are in place:

### Automounting ServiceAccount Token
The `automountServiceAccountToken` field is set to `false` for the `argocd-redis-ha` ServiceAccount.

**Rationale:** Unless the Redis HA components explicitly need to talk to the Kubernetes API, this can be safely set to false to reduce the attack surface. An attacker who gains access to a Redis HA pod will not have an automatically mounted ServiceAccount token to authenticate against the Kubernetes API server.

**File:** `platform/infrastructure/argocd/redis-ha/redis-ha-rbac.yaml`
