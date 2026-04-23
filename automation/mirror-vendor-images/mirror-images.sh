#!/usr/bin/env bash
set -euo pipefail
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <images.txt>"
  exit 2
fi
IMAGES_FILE="$1"
if command -v skopeo >/dev/null 2>&1; then
  COPIER="skopeo copy --all"
elif command -v crane >/dev/null 2>&1; then
  COPIER="crane cp"
else
  echo "Neither skopeo nor crane found. Install one to run mirroring." >&2
  exit 3
fi
while read -r src dst; do
  # skip empty lines and comment lines
  if [ -z "${src:-}" ] || [[ "${src}" == \#* ]]; then
    continue
  fi
  echo "Mirroring $src -> $dst"
  if [[ "$COPIER" == skopeo* ]]; then
    skopeo copy --all "docker://${src}" "docker://${dst}" || echo "skopeo failed for $src"
  else
    crane cp "$src" "$dst" || echo "crane failed for $src"
  fi
done < "$IMAGES_FILE"
