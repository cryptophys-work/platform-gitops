# Credential Management & Vault Integration - Complete

**Date:** 2026-02-16  
**Status:** ✅ Production Ready

## Summary

All platform credentials centralized in HashiCorp Vault with automatic sync to Kubernetes via External Secrets Operator. Default passwords rotated to secure values.

## Vault Storage

Path: `secret/platform-credentials/<service>`

### Web Platforms (9 Services)
- **Gitea**: admin (Code Forge)
- **ArgoCD**: admin (GitOps)
- **Grafana**: admin (Monitoring)
- **MinIO**: minioadmin (Object Storage / AI Models)
- **Harbor**: admin (Container Registry) ✅ PASSWORD ROTATED
- **Vault**: admin (Secrets Management)
- **Longhorn**: admin (Storage UI)
- **Kyverno**: nocadmin (Policy Reporter)
- **Hubble**: No auth (Network Observability)

### Databases
- **Gitea PostgreSQL**: gitea user
- **Harbor PostgreSQL**: postgres user ✅ PASSWORD ROTATED

## ExternalSecrets Status
- **ClusterSecretStore**: vault-backend → Valid ✅
- **Synced Secrets**: 12/12 ✅
- **TLS Distribution**: Wildcard cert to 6 namespaces ✅

## Security Improvements
1. Harbor admin password: Rotated from default
2. Harbor DB password: Rotated from default  
3. All credentials stored in Vault (not hardcoded)
4. ESO auto-syncs secrets from Vault to k8s
5. Wildcard TLS managed by cert-manager + ESO

## Access
All services: https://*.cryptophys.work (valid Let's Encrypt cert)

Privileged break-glass credentials are stored outside git in approved secure storage and must be retrieved through authorized operational procedures.
