#!/usr/bin/env bash
set -euo pipefail

MODEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${MODEL_DIR}/../.." && pwd)"
UI_DIR="${MODEL_DIR}/WithUI"
MODELCTL="${REPO_ROOT}/Llamacpp/modelctl.sh"
CONFIG_FILE="${MODEL_DIR}/config.env"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  cp "${MODEL_DIR}/config.env.example" "${CONFIG_FILE}"
  echo "Created ${CONFIG_FILE} from config.env.example"
fi

set -a
source "${CONFIG_FILE}"
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
    echo "[Qwen] required offline image is missing: ${image}" >&2
    echo "[Qwen] build or load the image before using UI mode." >&2
    exit 1
  fi
done

"${MODELCTL}" stop

docker volume inspect "${UI_VOLUME}" >/dev/null 2>&1 \
  || docker volume create "${UI_VOLUME}" >/dev/null

docker compose \
  --project-directory "${UI_DIR}" \
  --env-file "${CONFIG_FILE}" \
  -f "${UI_DIR}/docker-compose.yml" \
  up -d --no-build --pull never --remove-orphans

echo "[Qwen] Qwen/Open WebUI started from local images only."
echo "[Qwen] API: http://127.0.0.1:${PORT:-8080}/v1/models"
echo "[Qwen] UI:  http://127.0.0.1:${OPEN_WEBUI_PORT:-3000}"
