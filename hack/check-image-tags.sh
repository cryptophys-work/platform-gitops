#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_FILE="${SCRIPT_DIR}/validation-targets.txt"

# Match Kubernetes container image fields using an explicit :latest tag.
# Restrict to lines whose YAML key is `image:` so CRD description text
# (e.g. "if :latest tag is specified") does not false-positive.
IMAGE_LATEST_PATTERN="^[[:space:]]*image:[[:space:]]+.+:latest([[:space:]#'\"]|$)"

if ! command -v kustomize >/dev/null 2>&1; then
  echo "error: kustomize is not installed or not on PATH; install kustomize and retry" >&2
  exit 2
fi

if [[ ! -f "${TARGET_FILE}" ]]; then
  echo "error: targets file not found: ${TARGET_FILE}" >&2
  exit 2
fi

violations=0

while IFS= read -r target || [[ -n "${target}" ]]; do
  [[ -z "${target//[[:space:]]/}" ]] && continue
  [[ "${target}" =~ ^[[:space:]]*# ]] && continue

  echo "[check-image-tags] ${target}" >&2

  build_out="$(mktemp)"
  stderr_out="$(mktemp)"

  if ! kustomize build "${ROOT_DIR}/${target}" >"${build_out}" 2>"${stderr_out}"; then
    echo "error: kustomize build failed for ${target}" >&2
    cat "${stderr_out}" >&2
    rm -f "${build_out}" "${stderr_out}"
    exit 1
  fi

  if grep_output=$(grep -nE "${IMAGE_LATEST_PATTERN}" "${build_out}"); then
    violations=1
    echo "error: :latest image reference(s) in rendered manifest for ${target}:" >&2
    echo "${grep_output}" | sed "s|^|${target}:|" >&2
  fi

  rm -f "${build_out}" "${stderr_out}"
done < "${TARGET_FILE}"

if [[ "${violations}" -ne 0 ]]; then
  echo "error: one or more kustomize targets render container images with :latest" >&2
  exit 1
fi

echo "success: no :latest container image tags in rendered targets" >&2
