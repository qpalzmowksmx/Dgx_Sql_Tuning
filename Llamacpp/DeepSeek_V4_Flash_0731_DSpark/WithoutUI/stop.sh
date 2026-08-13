#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
LLAMACPP_DIR="$(cd -- "${MODEL_DIR}/.." && pwd)"
[[ -f "${MODEL_DIR}/config.env" ]] || cp "${MODEL_DIR}/config.env.example" "${MODEL_DIR}/config.env"

"${LLAMACPP_DIR}/offline_proxy.sh" stop || true

docker compose \
  --project-directory "${SCRIPT_DIR}" \
  --env-file "${MODEL_DIR}/config.env" \
  --env-file "${MODEL_DIR}/runtime.env" \
  -f "${SCRIPT_DIR}/docker-compose.yml" \
  down --remove-orphans
