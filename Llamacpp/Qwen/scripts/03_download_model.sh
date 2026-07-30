#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

if [[ -n "${HF_GGUF_MODEL_REF}" ]]; then
  echo "HF_GGUF_MODEL_REF is set; llama-server will download/use GGUF from Hugging Face cache."
  echo "Skipping source model download."
  exit 0
fi

mkdir -p "${HF_MODEL_DIR}"

"$(venv_hf)" download "${MODEL_REPO}" \
  --revision "${MODEL_REVISION}" \
  --local-dir "${HF_MODEL_DIR}" \
  --local-dir-use-symlinks False

echo "Model downloaded: ${HF_MODEL_DIR}"
