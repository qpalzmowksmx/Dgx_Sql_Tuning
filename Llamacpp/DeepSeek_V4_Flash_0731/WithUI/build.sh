#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
source "${MODEL_DIR}/scripts/common.sh"
load_config
docker compose --project-directory "${SCRIPT_DIR}" --env-file "${MODEL_DIR}/config.env" \
  -f "${SCRIPT_DIR}/docker-compose.yml" build deepseek-iq3-xxs
docker image inspect "${DOCKER_IMAGE}" >/dev/null
printf '[DeepSeek IQ3_XXS] built %s\n' "${DOCKER_IMAGE}"
