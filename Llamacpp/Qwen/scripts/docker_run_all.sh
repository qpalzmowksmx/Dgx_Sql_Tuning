#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

require_cmd docker

if [[ ! -f config.env ]]; then
  echo "config.env not found. Creating it from config.env.example."
  cp config.env.example config.env
fi

./scripts/docker_build.sh

mkdir -p runtime/models

if [[ -n "${HF_GGUF_MODEL_REF}" ]]; then
  echo "Using Hugging Face GGUF directly: ${HF_GGUF_MODEL_REF}"
  echo "The first server start will populate the shared Hugging Face cache."
else
  docker run --rm -it \
    --gpus all \
    --name "${DOCKER_CONTAINER}-setup" \
    --env-file config.env \
    -e WORK_DIR="${CONTAINER_WORKDIR}/runtime" \
    -e LLAMA_CPP_DIR=/opt/llama.cpp \
    -e HF_MODEL_DIR="${CONTAINER_WORKDIR}/runtime/models/${MODEL_FAMILY}-hf" \
    -e GGUF_MODEL="${CONTAINER_WORKDIR}/runtime/models/${MODEL_FAMILY}-${GGUF_OUTTYPE}.gguf" \
    -v "$(pwd):${CONTAINER_WORKDIR}" \
    -v "$(pwd)/runtime:${CONTAINER_WORKDIR}/runtime" \
    -v "${DOCKER_HF_CACHE_VOLUME}:/root/.cache/huggingface" \
    -w "${CONTAINER_WORKDIR}" \
    "${DOCKER_IMAGE}" \
    bash -lc './scripts/03_download_model.sh && ./scripts/04_convert_gguf.sh'
fi

exec ./scripts/docker_start_server.sh
