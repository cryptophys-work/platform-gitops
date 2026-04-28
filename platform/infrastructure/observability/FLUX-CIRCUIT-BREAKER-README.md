# Flux Dependency Monitoring with Circuit Breaker Logic

## Overview
Advanced Flux GitOps monitoring with dependency-aware circuit breaker logic to prevent cascading failures in the GitOps pipeline.

## Circuit Breaker Alerts

### 1. FluxDependencyCircuitBreaker
- **Purpose**: Detects when multiple Kustomizations are failing in the same namespace
- **Logic**: Activates when >3 Kustomizations fail in a namespace with dependency failures
- **Action**: Prevents cascade by alerting for manual intervention
- **Severity**: Critical

### 2. FluxHelmReleaseDependencyFailure
- **Purpose**: Identifies HelmReleases failing due to Kustomization dependencies
- **Logic**: Triggers when HelmRelease fails and Kustomizations in same namespace are failing
- **Severity**: Warning

### 3. FluxSourceControllerBacklog
- **Purpose**: Detects when GitRepository reconciliation is backed up
- **Logic**: Low reconciliation rate (<0.1 per 5m) indicates source controller issues
- **Severity**: Warning

### 4. FluxReconciliationStuck
- **Purpose**: Identifies Flux resources that haven't reconciled for 30+ minutes
- **Logic**: Unknown status + no reconciliation activity for 30 minutes
- **Severity**: Critical

## Additional Flux Alerts

### Controller Health
- **FluxControllerDown**: Any Flux controller (helm, kustomize, source, etc.) is down
- **FluxReconciliationFailures**: General reconciliation failures across all resources
- **FluxSlowReconciliation**: P95 reconciliation duration >5 minutes
- **FluxDependencyFailure**: Multiple failures in same namespace

## Circuit Breaker Logic Implementation

The circuit breaker uses PromQL expressions to:
1. **Detect cascading failures**: Multiple dependent resources failing
2. **Prevent resource exhaustion**: Alert before all resources fail
3. **Enable manual intervention**: Allow operators to suspend failing dependencies
4. **Monitor recovery**: Track when circuit breaker conditions are resolved

## Metrics Used
- `gotk_reconcile_condition`: Resource ready status
- `gotk_reconcile_duration_seconds`: Reconciliation timing
- `up{namespace="flux-system"}`: Controller health

## Runbook Actions
- **Circuit Breaker Activated**: Check Flux Kustomization dependency order, suspend failing dependencies
- **Dependency Failure**: Review namespace-specific Flux resources, fix root cause
- **Stuck Reconciliation**: Check source connectivity, restart controllers if needed