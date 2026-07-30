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

# Keep the WithUI profile aligned with the profile used by run_files.sh.
export CONTEXT_SIZE="${CONTEXT_SIZE:-${CTX_SIZE:-65536}}"
export REPEAT_PENALTY="${REPEAT_PENALTY:-${REPETITION_PENALTY:-1.0}}"

MODEL_IMAGE="${DOCKER_IMAGE:-llm-sql-dsv4-iq3xxs-dgx-spark:cuda13}"
UI_IMAGE="${OPEN_WEBUI_IMAGE:-llm-sql-open-webui:v0.9.4-dgx-stats}"
UI_VOLUME="${OPEN_WEBUI_DATA_VOLUME:-llm-sql-open-webui-data}"

for image in "${MODEL_IMAGE}" "${UI_IMAGE}"; do
  if ! docker image inspect "${image}" >/dev/null 2>&1; then
    echo "[DeepSeek] required offline image is missing: ${image}" >&2
    echo "[DeepSeek] build or load the image before using UI mode." >&2
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

echo "[DeepSeek] DeepSeek V4 Flash/Open WebUI started from local images only."
echo "[DeepSeek] API: http://127.0.0.1:${PORT:-8080}/v1/models"
echo "[DeepSeek] UI:  http://127.0.0.1:${OPEN_WEBUI_PORT:-3000}"
