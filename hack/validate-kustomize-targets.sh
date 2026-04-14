#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET_FILE="${SCRIPT_DIR}/validation-targets.txt"

ci_mode=0
while [[ "${#}" -gt 0 ]]; do
  case "${1}" in
    --ci-mode)
      ci_mode=1
      ;;
    *)
      echo "error: unknown argument: ${1}" >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "${ci_mode}" -eq 1 ]]; then
  echo "Running in CI mode"
fi

if ! command -v kustomize >/dev/null 2>&1; then
  echo "error: kustomize is not installed or not on PATH; install kustomize and retry" >&2
  exit 2
fi

if [[ ! -f "${TARGET_FILE}" ]]; then
  echo "error: targets file not found: ${TARGET_FILE}" >&2
  exit 2
fi

failures=0
stderr_file="$(mktemp)"
trap 'rm -f "${stderr_file}"' EXIT

while IFS= read -r target || [[ -n "${target}" ]]; do
  [[ -z "${target//[[:space:]]/}" ]] && continue
  echo "[validate] ${target}"
  if kustomize build "${ROOT_DIR}/${target}" >/dev/null 2>"${stderr_file}"; then
    echo "[pass] ${target}"
  else
    echo "[fail] ${target}"
    head -n 40 "${stderr_file}"
    failures=$((failures + 1))
  fi
done < "${TARGET_FILE}"

if [[ "${failures}" -gt 0 ]]; then
  echo "error: ${failures} kustomize build target(s) failed" >&2
  exit 1
fi

echo "success: all kustomize build targets passed"
