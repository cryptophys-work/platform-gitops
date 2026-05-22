#!/bin/bash
# Script to rename numeric-prefixed YAML files to semantic naming

rename_kustomization() {
    local dir=$1
    cd "$dir" || return
    
    # Rename files to semantic names
    [ -f "00-crds.yaml" ] && mv "00-crds.yaml" "01-crds.yaml"
    [ -f "01-namespaces.yaml" ] && mv "01-namespaces.yaml" "02-namespaces.yaml"
    [ -f "02-scheduling.yaml" ] && mv "02-scheduling.yaml" "03-scheduling.yaml"
    [ -f "05-sources.yaml" ] && mv "05-sources.yaml" "04-flux-sources.yaml"
    [ -f "10-controllers.yaml" ] && mv "10-controllers.yaml" "05-controllers.yaml"
    [ -f "10-database.yaml" ] && mv "10-database.yaml" "06-database.yaml"
    [ -f "12-certificates.yaml" ] && mv "12-certificates.yaml" "07-certificates.yaml"
    [ -f "15-dns-core.yaml" ] && mv "15-dns-core.yaml" "08-dns-core.yaml"
    [ -f "15-security-runtime.yaml" ] && mv "15-security-runtime.yaml" "09-security-runtime.yaml"
    [ -f "17-metallb.yaml" ] && mv "17-metallb.yaml" "10-metallb.yaml"
    [ -f "18-networking.yaml" ] && mv "18-networking.yaml" "11-networking.yaml"
    [ -f "20-policy.yaml" ] && mv "20-policy.yaml" "12-policies.yaml"
    [ -f "30-storage.yaml" ] && mv "30-storage.yaml" "13-storage.yaml"
    [ -f "34-harbor.yaml" ] && mv "34-harbor.yaml" "14-harbor.yaml"
    [ -f "37-argocd.yaml" ] && mv "37-argocd.yaml" "15-argocd.yaml"
    [ -f "38-observability.yaml" ] && mv "38-observability.yaml" "16-observability.yaml"
    [ -f "42-ray.yaml" ] && mv "42-ray.yaml" "17-ray.yaml"
    [ -f "45-gateway.yaml" ] && mv "45-gateway.yaml" "18-gateway.yaml"
    
    echo "Renamed in $dir"
}

# Apply to archived clusters (read-only reference)
# rename_kustomization "clusters/talos-prod.ARCHIVED/kustomization"
# rename_kustomization "clusters/cryptophys-genesis.ARCHIVED/kustomization"
