#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LLAMACPP_DIR="$(cd "${MODEL_DIR}/.." && pwd)"

if [[ ! -f "${MODEL_DIR}/config.env" ]]; then
  cp "${MODEL_DIR}/config.env.example" "${MODEL_DIR}/config.env"
  echo "Created ${MODEL_DIR}/config.env from config.env.example"
fi

"${LLAMACPP_DIR}/modelctl.sh" stop

set -a
source "${MODEL_DIR}/config.env"
set +a
OPEN_WEBUI_VOLUME="${OPEN_WEBUI_DATA_VOLUME:-llm-sql-open-webui-data}"
docker volume inspect "${OPEN_WEBUI_VOLUME}" >/dev/null 2>&1 \
  || docker volume create "${OPEN_WEBUI_VOLUME}" >/dev/null

exec docker compose \
  --project-directory "${SCRIPT_DIR}" \
  --env-file "${MODEL_DIR}/config.env" \
  -f "${SCRIPT_DIR}/docker-compose.yml" \
  up -d --build --remove-orphans
