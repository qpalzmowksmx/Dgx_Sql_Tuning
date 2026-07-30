#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

if [[ -z "${HF_GGUF_MODEL_REF}" ]]; then
  echo "HF_GGUF_MODEL_REF is empty. Set it to repo:quant, for example:" >&2
  echo "  HF_GGUF_MODEL_REF=owner/qwen-gguf-repository:BF16" >&2
  exit 1
fi

exec ./scripts/05_start_llama_server.sh
