#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

exec docker compose \
  --project-directory "${SCRIPT_DIR}" \
  --env-file "${MODEL_DIR}/config.env" \
  -f "${SCRIPT_DIR}/docker-compose.yml" \
  down --remove-orphans
