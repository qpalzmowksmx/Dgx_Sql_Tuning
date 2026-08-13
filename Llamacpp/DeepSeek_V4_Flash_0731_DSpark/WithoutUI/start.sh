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
  "${PORT:-8080}" "${PORT:-8080}"

printf '[DS4] API ready: http://%s:%s/v1/models\n' \
  "${BIND_ADDRESS:-127.0.0.1}" "${PORT:-8080}"
