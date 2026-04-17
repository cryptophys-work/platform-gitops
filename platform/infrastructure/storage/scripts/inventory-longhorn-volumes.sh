#!/usr/bin/env bash
# Live cluster inventory: PVCs and Longhorn Volume/node resources. Requires kubectl.
set -euo pipefail

echo "=== PVCs (all namespaces) ==="
kubectl get pvc -A -o wide

echo
echo "=== Longhorn volumes (longhorn-system) ==="
if kubectl get volumes.longhorn.io -n longhorn-system &>/dev/null; then
  kubectl get volumes.longhorn.io -n longhorn-system -o wide 2>/dev/null || true
else
  echo "volumes.longhorn.io not available (missing CRD or RBAC)."
fi

echo
echo "=== Longhorn nodes ==="
if kubectl get nodes.longhorn.io -n longhorn-system &>/dev/null; then
  kubectl get nodes.longhorn.io -n longhorn-system -o wide 2>/dev/null || true
else
  echo "nodes.longhorn.io not available."
fi
