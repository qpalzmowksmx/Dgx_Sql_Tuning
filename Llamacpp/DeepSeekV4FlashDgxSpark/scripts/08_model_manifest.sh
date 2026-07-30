#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

require_cmd sha256sum

if [[ ! -d "${MODEL_CACHE_DIR}" ]]; then
  echo "Model cache does not exist: ${MODEL_CACHE_DIR}" >&2
  exit 1
fi

mapfile -d '' model_files < <(find "${MODEL_CACHE_DIR}" -type f -name '*.gguf' -print0 | sort -z)
if [[ "${#model_files[@]}" == "0" ]]; then
  echo "No GGUF shards found in ${MODEL_CACHE_DIR}. Load the model first." >&2
  exit 1
fi

printf '# model=%s\n' "${HF_GGUF_MODEL_REF}"
printf '# generated_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
for model_file in "${model_files[@]}"; do
  sha256sum "${model_file}"
done

