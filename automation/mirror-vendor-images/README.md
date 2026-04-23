Mirror vendor images to local Harbor registry (registry.cryptophys.work)

This directory holds a simple mirroring helper to seed high-impact upstream images
into the local Harbor registry so ImagePullBackOff caused by external outages
or rate-limits is reduced.

Usage:
  - Edit images.txt with lines: <source_image> <dest_image>
  - Ensure a CI runner or local host has credentials to push to registry.cryptophys.work
  - Run the mirroring script: ./mirror-images.sh images.txt

Notes:
  - The script uses 'skopeo' (preferred) or 'crane' if available.
  - Start by mirroring Keycloak, Headlamp, oauth2-proxy, postgres, and any app images
    that currently show ImagePullBackOff in the cluster.
  - After mirroring, update app manifests to pin to the mirrored image tags/sha.

Example images.txt entries:
  quay.io/keycloak/keycloak:20.0.3 registry.cryptophys.work/library/keycloak:20.0.3
  ghcr.io/headlamp/headlamp:v0.40.1 registry.cryptophys.work/library/headlamp:v0.40.1
  quay.io/oauth2-proxy/oauth2-proxy:v7.6.0 registry.cryptophys.work/library/oauth2-proxy:v7.6.0

