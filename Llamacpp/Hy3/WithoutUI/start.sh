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
IMAGE_NAME="${DOCKER_IMAGE:-llm-sql-hy3-iq1m-mtp-dgx-spark:cuda13}"

if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
  echo "[Hy3] required offline image is missing: ${IMAGE_NAME}" >&2
  echo "[Hy3] load the offline Docker image bundle or build it while online." >&2
  exit 1
fi

"${LLAMACPP_DIR}/modelctl.sh" stop

docker compose \
  --project-directory "${SCRIPT_DIR}" \
  --env-file "${MODEL_DIR}/config.env" \
  -f "${SCRIPT_DIR}/docker-compose.yml" \
  up -d --no-build --pull never --remove-orphans

"${LLAMACPP_DIR}/offline_proxy.sh" start \
  "${DOCKER_CONTAINER:-llm-sql-hy3-iq1m-mtp-dgx-spark}" "${PORT:-8080}" "${PORT:-8080}"
