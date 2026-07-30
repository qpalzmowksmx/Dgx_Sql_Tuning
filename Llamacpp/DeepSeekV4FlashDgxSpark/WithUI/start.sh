#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
LLAMACPP_DIR="$(cd -- "${MODEL_DIR}/.." && pwd)"

COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
CONFIG_FILE="${SCRIPT_DIR}/.env"
MODELCTL="${LLAMACPP_DIR}/modelctl.sh"

log() {
  printf '[DeepSeekV4Flash] %s\n' "$*"
}

die() {
  printf '[DeepSeekV4Flash] ERROR: %s\n' "$*" >&2
  exit 1
}

trap 'die "Command failed at line ${LINENO}: ${BASH_COMMAND}"' ERR

[[ -f "${COMPOSE_FILE}" ]] \
  || die "Compose file not found: ${COMPOSE_FILE}"

[[ -f "${CONFIG_FILE}" ]] \
  || die "Environment file not found: ${CONFIG_FILE}"

set -a
# shellcheck disable=SC1090
source "${CONFIG_FILE}"
set +a

OPEN_WEBUI_VOLUME="${OPEN_WEBUI_DATA_VOLUME:-llm-sql-open-webui-data}"
MODEL_CONTAINER="${DOCKER_CONTAINER:-llm-sql-dsv4-iq3xxs-dgx-spark}"

if [[ -x "${MODELCTL}" ]]; then
  log "Stopping currently managed model services"
  "${MODELCTL}" stop
else
  log "modelctl.sh not found or not executable; skipping common model stop"
fi

if ! docker volume inspect "${OPEN_WEBUI_VOLUME}" >/dev/null 2>&1; then
  log "Creating external OpenWebUI volume: ${OPEN_WEBUI_VOLUME}"
  docker volume create "${OPEN_WEBUI_VOLUME}" >/dev/null
fi

COMPOSE_CMD=(
  docker compose
  --project-directory "${SCRIPT_DIR}"
  --env-file "${CONFIG_FILE}"
  -f "${COMPOSE_FILE}"
)

log "Validating Compose configuration"
"${COMPOSE_CMD[@]}" config --quiet

log "Starting DeepSeek V4 Flash and OpenWebUI"

if ! "${COMPOSE_CMD[@]}" up \
  -d \
  --build \
  --remove-orphans
then
  log "Compose startup failed"

  docker ps -a \
    --filter "name=${MODEL_CONTAINER}" \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' \
    || true

  docker inspect "${MODEL_CONTAINER}" \
    --format 'status={{.State.Status}} exit={{.State.ExitCode}} error={{.State.Error}} restart={{.RestartCount}}' \
    2>/dev/null \
    || true

  docker logs \
    --tail 300 \
    "${MODEL_CONTAINER}" \
    2>&1 \
    || true

  exit 1
fi

log "Compose services started"