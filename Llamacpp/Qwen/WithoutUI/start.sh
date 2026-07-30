#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LLAMACPP_DIR="$(cd "${MODEL_DIR}/.." && pwd)"

if [[ ! -f "${MODEL_DIR}/config.env" ]]; then
  cp "${MODEL_DIR}/config.env.example" "${MODEL_DIR}/config.env"
  echo "Created ${MODEL_DIR}/config.env from config.env.example"
fi

set -a
source "${MODEL_DIR}/config.env"
set +a

# AutorunEnum can select the quality-first profile without rewriting the
# machine-local config.env. Existing manual profiles remain available when
# these QWEN_* overrides are not supplied.
if [[ -n "${QWEN_CTX_SIZE:-}" ]]; then
  export CTX_SIZE="${QWEN_CTX_SIZE}"
fi
if [[ -n "${QWEN_LLAMA_SERVER_EXTRA_ARGS:-}" ]]; then
  export LLAMA_SERVER_EXTRA_ARGS="${QWEN_LLAMA_SERVER_EXTRA_ARGS}"
fi

IMAGE_NAME="${DOCKER_IMAGE:-llamacpp-qwen-server:cuda}"

if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
  echo "[Qwen] required offline image is missing: ${IMAGE_NAME}" >&2
  echo "[Qwen] load the offline Docker image bundle or run scripts/docker_build.sh while online." >&2
  exit 1
fi

"${LLAMACPP_DIR}/modelctl.sh" stop

docker compose \
  --project-directory "${SCRIPT_DIR}" \
  --env-file "${MODEL_DIR}/config.env" \
  -f "${SCRIPT_DIR}/docker-compose.yml" \
  up -d --no-build --pull never --remove-orphans

"${LLAMACPP_DIR}/offline_proxy.sh" start \
  "${DOCKER_CONTAINER:-llamacpp-qwen-server}" "${PORT:-8080}" "${PORT:-8080}"
