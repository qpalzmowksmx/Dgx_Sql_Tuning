#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
ensure_config
load_config

require_cmd docker

mkdir -p runtime/models

docker rm -f "${DOCKER_CONTAINER}" >/dev/null 2>&1 || true

exec docker run --rm -it \
  --gpus all \
  --name "${DOCKER_CONTAINER}" \
  --env-file config.env \
  -e WORK_DIR="${CONTAINER_WORKDIR}/runtime" \
  -e LLAMA_CPP_DIR=/opt/llama.cpp \
  -e HF_MODEL_DIR="${CONTAINER_WORKDIR}/runtime/models/${MODEL_FAMILY}-hf" \
  -e GGUF_MODEL="${CONTAINER_WORKDIR}/runtime/models/$(basename "${GGUF_MODEL}")" \
  -e HOST=0.0.0.0 \
  -p "${BIND_ADDRESS}:${PORT}:${PORT}" \
  -v "$(pwd):${CONTAINER_WORKDIR}" \
  -v "$(pwd)/runtime:${CONTAINER_WORKDIR}/runtime" \
  -v "${DOCKER_HF_CACHE_VOLUME}:/root/.cache/huggingface" \
  -w "${CONTAINER_WORKDIR}" \
  "${DOCKER_IMAGE}" \
  ./scripts/start_llama_server.sh
