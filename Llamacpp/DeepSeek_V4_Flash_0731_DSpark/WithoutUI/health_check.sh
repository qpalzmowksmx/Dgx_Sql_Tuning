#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
set -a
# shellcheck disable=SC1090
source "${MODEL_DIR}/config.env"
# shellcheck disable=SC1090
source "${MODEL_DIR}/runtime.env"
set +a

curl --fail --silent --show-error --max-time 15 \
  "http://${BIND_ADDRESS:-127.0.0.1}:${PORT:-8080}/v1/models" >/dev/null
printf '[DS4] model API is healthy\n'
