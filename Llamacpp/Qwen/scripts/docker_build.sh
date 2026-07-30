#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

require_cmd docker

docker build \
  -f docker/Dockerfile \
  --build-arg CUDA_IMAGE="${DOCKER_CUDA_IMAGE}" \
  --build-arg LLAMA_CPP_REPO="${LLAMA_CPP_REPO}" \
  --build-arg LLAMA_CPP_REF="${LLAMA_CPP_REF}" \
  -t "${DOCKER_IMAGE}" \
  .

echo "Docker image built: ${DOCKER_IMAGE}"
