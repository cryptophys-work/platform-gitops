#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

failures=0

while IFS= read -r kustomization_file; do
  echo "[order] checking ${kustomization_file#${ROOT_DIR}/}"
  prev_stage=-1
  line_no=0
  while IFS= read -r resource; do
    line_no=$((line_no + 1))
    stage="$(printf '%s' "${resource}" | sed -n 's#.*/\([0-9][0-9]\)-.*#\1#p')"
    if [[ -z "${stage}" ]]; then
      continue
    fi
    stage_num=$((10#${stage}))
    if (( stage_num < prev_stage )); then
      echo "error: stage order regression in ${kustomization_file#${ROOT_DIR}/} at resource '${resource}' (line ${line_no})" >&2
      echo "       stage ${stage} appears after stage $(printf '%02d' "${prev_stage}")" >&2
      failures=$((failures + 1))
      break
    fi
    prev_stage=${stage_num}
  done < <(
    awk '/^resources:/{in_resources=1; next} in_resources && /^[[:space:]]+- /{print $2} in_resources && !/^[[:space:]]+- /{in_resources=0}' "${kustomization_file}"
  )
done < <(rg --files "${ROOT_DIR}/clusters" | rg 'kustomization.yaml$')

if [[ "${failures}" -gt 0 ]]; then
  echo "error: ${failures} cluster kustomization file(s) violate non-decreasing stage order" >&2
  exit 1
fi

echo "success: cluster stage ordering is consistent"
