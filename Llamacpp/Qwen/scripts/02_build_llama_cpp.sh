#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

if [[ ! -d "${LLAMA_CPP_DIR}/.git" ]]; then
  git clone "${LLAMA_CPP_REPO}" "${LLAMA_CPP_DIR}"
else
  git -C "${LLAMA_CPP_DIR}" fetch --all --tags
fi

git -C "${LLAMA_CPP_DIR}" checkout "${LLAMA_CPP_REF}"
git -C "${LLAMA_CPP_DIR}" pull --ff-only || true

cmake \
  -S "${LLAMA_CPP_DIR}" \
  -B "${LLAMA_CPP_DIR}/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_CUDA=ON \
  -DLLAMA_CURL=ON

cmake --build "${LLAMA_CPP_DIR}/build" --config Release -j "$(nproc)"

if [[ ! -x "${LLAMA_CPP_DIR}/build/bin/llama-server" ]]; then
  echo "llama-server binary was not found after build." >&2
  exit 1
fi

echo "llama.cpp build complete: ${LLAMA_CPP_DIR}/build/bin/llama-server"
