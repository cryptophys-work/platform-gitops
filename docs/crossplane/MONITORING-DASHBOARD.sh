#!/bin/bash
# Cluster Health Monitoring Dashboard
# Purpose: Real-time monitoring of cluster status during recovery
# Usage: ./MONITORING-DASHBOARD.sh [watch-interval]
# Example: ./MONITORING-DASHBOARD.sh 5  # Update every 5 seconds

INTERVAL=${1:-10}  # Default 10 second update interval

clear_screen() {
  clear
  echo "╔════════════════════════════════════════════════════════════════════╗"
  echo "║         CRYPTOPHYS-GENESIS CLUSTER HEALTH DASHBOARD               ║"
  echo "║                     Last Update: $(date '+%Y-%m-%d %H:%M:%S')                   ║"
  echo "╚════════════════════════════════════════════════════════════════════╝"
  echo ""
}

print_node_status() {
  echo "┌─ NODE STATUS ─────────────────────────────────────────────────────┐"

  # Count nodes by status
  local ready_count=$(kubectl get nodes -o json 2>/dev/null | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length')
  local notready_count=$(kubectl get nodes -o json 2>/dev/null | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status!="True"))] | length')
  local total_nodes=$(kubectl get nodes -o json 2>/dev/null | jq '.items | length')

  if [ -z "$ready_count" ] || [ "$total_nodes" = "null" ]; then
    echo "│ ❌ Cannot reach API server"
  else
    local status="✓"
    [ "$notready_count" -gt 0 ] && status="✗"
    echo "│ ${status} Ready: ${ready_count}/${total_nodes} | NotReady: ${notready_count}"

    # List all nodes with status
    kubectl get nodes -o wide 2>/dev/null | tail -n +2 | awk '{
      status = $2
      icon = "✓"
      if (status != "Ready") icon = "✗"
      printf "│   %s %-35s %s\n", icon, $1, status
    }'
  fi
  echo "└────────────────────────────────────────────────────────────────────┘"
}

print_cilium_status() {
  echo "┌─ CILIUM/CNI STATUS ────────────────────────────────────────────────┐"

  # Count Cilium pod status
  local cilium_ready=$(kubectl get daemonset -n cilium-system cilium -o json 2>/dev/null | jq '.status.numberReady // 0')
  local cilium_desired=$(kubectl get daemonset -n cilium-system cilium -o json 2>/dev/null | jq '.status.desiredNumberScheduled // 0')

  if [ -z "$cilium_ready" ]; then
    echo "│ ❌ Cannot query Cilium status"
  else
    local status="✓"
    [ "$cilium_ready" -lt "$cilium_desired" ] && status="✗"
    echo "│ ${status} Cilium Agent Pods: ${cilium_ready}/${cilium_desired}"

    # Check for CrashLoopBackOff
    local crashloops=$(kubectl get pod -n cilium-system -l k8s-app=cilium --field-selector=status.phase!=Running 2>/dev/null | tail -n +2 | wc -l)
    if [ "$crashloops" -gt 0 ]; then
      echo "│ ⚠️  CrashLoopBackOff pods: ${crashloops}"
    fi

    # Check Cilium operator
    local operator_ready=$(kubectl get deployment -n cilium-system cilium-operator -o json 2>/dev/null | jq '.status.readyReplicas // 0')
    local operator_desired=$(kubectl get deployment -n cilium-system cilium-operator -o json 2>/dev/null | jq '.spec.replicas // 0')
    local operator_status="✓"
    [ "$operator_ready" -lt "$operator_desired" ] && operator_status="✗"
    echo "│ ${operator_status} Cilium Operator: ${operator_ready}/${operator_desired}"
  fi
  echo "└────────────────────────────────────────────────────────────────────┘"
}

print_kyverno_status() {
  echo "┌─ KYVERNO WEBHOOK STATUS ──────────────────────────────────────────┐"

  # Check webhook endpoints
  local endpoints=$(kubectl get endpoints -n kyverno-system kyverno-svc -o json 2>/dev/null | jq '.subsets[0].addresses | length // 0')

  if [ -z "$endpoints" ]; then
    echo "│ ❌ Cannot query Kyverno endpoints"
  else
    local status="✓"
    [ "$endpoints" -eq 0 ] && status="✗"
    echo "│ ${status} Webhook Endpoints: ${endpoints}"

    # Check Kyverno pod readiness
    local kyverno_ready=$(kubectl get deployment -n kyverno-system kyverno -o json 2>/dev/null | jq '.status.readyReplicas // 0')
    local kyverno_desired=$(kubectl get deployment -n kyverno-system kyverno -o json 2>/dev/null | jq '.spec.replicas // 0')
    local kyverno_status="✓"
    [ "$kyverno_ready" -lt "$kyverno_desired" ] && kyverno_status="✗"
    echo "│ ${kyverno_status} Kyverno Pods: ${kyverno_ready}/${kyverno_desired}"
  fi
  echo "└────────────────────────────────────────────────────────────────────┘"
}

print_api_server_status() {
  echo "┌─ API SERVER STATUS ────────────────────────────────────────────────┐"

  # Test API connectivity
  local api_response=$(kubectl cluster-info 2>&1 | head -1)

  if [[ "$api_response" == *"Kubernetes master"* ]]; then
    echo "│ ✓ API Server: Responding"

    # Check API pod status
    local api_ready=$(kubectl get deployment -n kube-system kube-apiserver -o json 2>/dev/null | jq '.status.readyReplicas // 0')
    [ "$api_ready" -eq 0 ] && api_ready=$(kubectl get pod -n kube-system -l component=kube-apiserver --field-selector=status.phase=Running 2>/dev/null | tail -n +2 | wc -l)
    echo "│ ℹ️  API Server Pods Running: ${api_ready:-unknown}"
  else
    echo "│ ❌ API Server: Not responding (timeout/connection refused)"
  fi
  echo "└────────────────────────────────────────────────────────────────────┘"
}

print_etcd_status() {
  echo "┌─ ETCD STATUS ──────────────────────────────────────────────────────┐"

  # Check etcd member status
  local etcd_health=$(kubectl exec -n kube-system etcd-cortex-178-18-250-39 -- \
    etcdctl --endpoints=127.0.0.1:2379 endpoint health 2>/dev/null)

  if [[ "$etcd_health" == *"healthy"* ]]; then
    echo "│ ✓ etcd: Healthy"
    local healthy_members=$(echo "$etcd_health" | grep healthy | wc -l)
    echo "│ ℹ️  Healthy Members: ${healthy_members}/3"
  else
    echo "│ ⚠️  etcd: Status unknown (cannot connect)"
  fi
  echo "└────────────────────────────────────────────────────────────────────┘"
}

print_crossplane_status() {
  echo "┌─ CROSSPLANE STATUS ────────────────────────────────────────────────┐"

  # Check Crossplane provider status
  local providers=$(kubectl get providers -n crossplane-system 2>/dev/null | tail -n +2)

  if [ -n "$providers" ]; then
    echo "$providers" | awk '{
      status = $2
      icon = "✓"
      if (status != "True") icon = "⚠"
      printf "│ %s Provider: %s %s\n", icon, $1, status
    }'
  else
    echo "│ ℹ️  No providers installed or checking failed"
  fi

  # Check ManagedNode claims
  local managednodes=$(kubectl get managednodes -n crossplane-system -o json 2>/dev/null | jq '.items | length // 0')
  echo "│ ℹ️  ManagedNode Claims: ${managednodes}"

  echo "└────────────────────────────────────────────────────────────────────┘"
}

print_system_health() {
  echo "┌─ SYSTEM HEALTH SUMMARY ────────────────────────────────────────────┐"

  # Calculate overall health
  local nodes_healthy=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready")
  local total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)

  if [ "$total_nodes" -eq 0 ]; then
    echo "│ 🔴 CRITICAL: Cannot connect to cluster"
  elif [ "$nodes_healthy" -eq "$total_nodes" ]; then
    echo "│ 🟢 HEALTHY: All nodes ready"
  elif [ "$nodes_healthy" -gt 0 ]; then
    echo "│ 🟡 DEGRADED: Partial cluster availability (${nodes_healthy}/${total_nodes} nodes)"
  else
    echo "│ 🔴 CRITICAL: No nodes ready (${nodes_healthy}/${total_nodes})"
  fi

  echo "└────────────────────────────────────────────────────────────────────┘"
}

print_recommended_actions() {
  echo ""
  echo "RECOMMENDED ACTIONS:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local nodes_healthy=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready")
  local total_nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)

  if [ "$total_nodes" -eq 0 ]; then
    echo "• Cannot reach API server — see CLUSTER-RECOVERY-RUNBOOK.md Section 3.1"
  elif [ "$nodes_healthy" -eq "$total_nodes" ]; then
    echo "• Cluster is healthy — ready to execute P1-VALIDATION-CHECKLIST.md"
  elif [ "$nodes_healthy" -eq 0 ]; then
    echo "• All nodes NotReady — see CLUSTER-RECOVERY-RUNBOOK.md Section 3.2"
  else
    echo "• Some nodes failing — use 'kubectl drain <node>' and reboot individual nodes"
  fi

  echo ""
  echo "NEXT STEPS:"
  echo "1. Review recommendations above"
  echo "2. If healthy: Run 'P1-VALIDATION-CHECKLIST.md' (7 phases, 12 tests)"
  echo "3. If unhealthy: Follow recovery steps in CLUSTER-RECOVERY-RUNBOOK.md"
  echo "4. Press Ctrl+C to stop monitoring"
}

# Main loop
while true; do
  clear_screen
  print_api_server_status
  print_node_status
  print_cilium_status
  print_kyverno_status
  print_etcd_status
  print_crossplane_status
  echo ""
  print_system_health
  print_recommended_actions

  echo ""
  echo "⏱️  Updating in ${INTERVAL} seconds... (Ctrl+C to stop)"
  sleep "$INTERVAL"
done
