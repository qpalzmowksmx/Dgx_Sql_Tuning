#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODEL_DIR="${REPO_ROOT}/Llamacpp/Qwen"
UI_DIR="${MODEL_DIR}/WithUI"
MODELCTL="${REPO_ROOT}/Llamacpp/modelctl.sh"

if [[ ! -f "${MODEL_DIR}/config.env" ]]; then
  cp "${MODEL_DIR}/config.env.example" "${MODEL_DIR}/config.env"
  echo "Created ${MODEL_DIR}/config.env from config.env.example"
fi

set -a
source "${MODEL_DIR}/config.env"
set +a

if [[ -n "${QWEN_CTX_SIZE:-}" ]]; then
  export CTX_SIZE="${QWEN_CTX_SIZE}"
fi
if [[ -n "${QWEN_LLAMA_SERVER_EXTRA_ARGS:-}" ]]; then
  export LLAMA_SERVER_EXTRA_ARGS="${QWEN_LLAMA_SERVER_EXTRA_ARGS}"
fi

MODEL_IMAGE="${DOCKER_IMAGE:-llamacpp-qwen-server:cuda}"
UI_IMAGE="${OPEN_WEBUI_IMAGE:-llm-sql-open-webui:v0.9.4-dgx-stats}"
UI_VOLUME="${OPEN_WEBUI_DATA_VOLUME:-llm-sql-open-webui-data}"

for image in "${MODEL_IMAGE}" "${UI_IMAGE}"; do
  if ! docker image inspect "${image}" >/dev/null 2>&1; then
    echo "[AutorunEnum Final] required offline image is missing: ${image}" >&2
    echo "[AutorunEnum Final] load the offline image bundle before using UI mode." >&2
    exit 1
  fi
done

"${MODELCTL}" stop
docker volume inspect "${UI_VOLUME}" >/dev/null 2>&1 \
  || docker volume create "${UI_VOLUME}" >/dev/null

docker compose \
  --project-directory "${UI_DIR}" \
  --env-file "${MODEL_DIR}/config.env" \
  -f "${UI_DIR}/docker-compose.yml" \
  up -d --no-build --pull never --remove-orphans

echo "[AutorunEnum Final] Qwen/Open WebUI started from local images only."
