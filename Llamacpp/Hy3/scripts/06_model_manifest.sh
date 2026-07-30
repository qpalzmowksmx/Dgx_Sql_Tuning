#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

if [[ ! -f "${MODEL_PATH}" ]]; then
  echo "Model not found: ${MODEL_PATH}" >&2
  exit 1
fi

actual_size="$(file_size "${MODEL_PATH}")"
actual_sha="$(model_sha256 "${MODEL_PATH}")"

printf 'repository=%s\n' "${MODEL_REPO}"
printf 'revision=%s\n' "${MODEL_REVISION}"
printf 'file=%s\n' "${MODEL_FILE}"
printf 'path=%s\n' "${MODEL_PATH}"
printf 'size_bytes=%s\n' "${actual_size}"
printf 'sha256=%s\n' "${actual_sha}"

if [[ "${actual_size}" != "${MODEL_SIZE_BYTES}" || \
      "${actual_sha}" != "${MODEL_SHA256}" ]]; then
  echo "Model manifest does not match the pinned values." >&2
  exit 1
fi
echo "status=verified"

