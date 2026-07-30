#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

./scripts/01_prepare_dgx.sh
./scripts/02_build_llama_cpp.sh

source ./scripts/common.sh
load_config

if [[ -n "${HF_GGUF_MODEL_REF}" ]]; then
  echo "Using prebuilt Hugging Face GGUF: ${HF_GGUF_MODEL_REF}"
else
  ./scripts/03_download_model.sh
  ./scripts/04_convert_gguf.sh
fi

if [[ "${START_SERVER}" == "1" ]]; then
  exec ./scripts/05_start_llama_server.sh
fi

echo "Build/download/convert complete."
echo "Start server later with:"
echo "  ./scripts/start_llama_server.sh"
