#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

if [[ -n "${HF_GGUF_MODEL_REF}" ]]; then
  echo "HF_GGUF_MODEL_REF is set; using prebuilt GGUF from Hugging Face."
  echo "Skipping HF-to-GGUF conversion."
  exit 0
fi

CONVERT_SCRIPT="${LLAMA_CPP_DIR}/convert_hf_to_gguf.py"

if [[ ! -f "${CONVERT_SCRIPT}" ]]; then
  echo "Missing converter: ${CONVERT_SCRIPT}" >&2
  exit 1
fi

mkdir -p "$(dirname "${GGUF_MODEL}")"

"$(venv_python)" "${CONVERT_SCRIPT}" "${HF_MODEL_DIR}" \
  --outfile "${GGUF_MODEL}" \
  --outtype "${GGUF_OUTTYPE}"

echo "GGUF conversion complete: ${GGUF_MODEL}"
