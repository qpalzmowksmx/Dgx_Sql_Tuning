#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
LLAMACPP_DIR="$(cd -- "${MODEL_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${MODEL_DIR}/scripts/host_common.sh"
ds4_load_config "${MODEL_DIR}"
ds4_require_runtime "${MODEL_DIR}"

if [[ -x "${LLAMACPP_DIR}/modelctl.sh" ]]; then
  "${LLAMACPP_DIR}/modelctl.sh" stop
fi

if ! docker image inspect "${OPEN_WEBUI_IMAGE}" >/dev/null 2>&1; then
  printf '[DS4] Open WebUI image is missing: %s\n' "${OPEN_WEBUI_IMAGE}" >&2
  exit 1
fi
if ! docker volume inspect "${OPEN_WEBUI_DATA_VOLUME}" >/dev/null 2>&1; then
  docker volume create "${OPEN_WEBUI_DATA_VOLUME}" >/dev/null
fi

docker compose \
  --project-directory "${SCRIPT_DIR}" \
  --env-file "${MODEL_DIR}/config.env" \
  --env-file "${MODEL_DIR}/runtime.env" \
  -f "${SCRIPT_DIR}/docker-compose.yml" \
  up -d --no-build --pull never --remove-orphans

ds4_wait_for_health \
  "${DOCKER_CONTAINER:-deepseek-v4-flash-0731-dspark-server}" \
  "${MODEL_HEALTH_TIMEOUT_SEC:-7200}"
"${LLAMACPP_DIR}/offline_proxy.sh" start \
  "${DOCKER_CONTAINER:-deepseek-v4-flash-0731-dspark-server}" \
  "${PORT:-8080}" "${PORT:-8080}" ds4-api
ds4_wait_for_health \
  "${OPEN_WEBUI_CONTAINER:-deepseek-v4-flash-0731-dspark-open-webui}" \
  "${OPEN_WEBUI_HEALTH_TIMEOUT_SEC:-900}"
"${LLAMACPP_DIR}/offline_proxy.sh" start \
  "${OPEN_WEBUI_CONTAINER:-deepseek-v4-flash-0731-dspark-open-webui}" \
  8080 "${OPEN_WEBUI_PORT:-3000}" ds4-webui

printf '[DS4] API: http://%s:%s/v1/models\n' "${BIND_ADDRESS:-127.0.0.1}" "${PORT:-8080}"
printf '[DS4] UI:  http://%s:%s\n' "${OPEN_WEBUI_BIND_ADDRESS:-127.0.0.1}" "${OPEN_WEBUI_PORT:-3000}"
