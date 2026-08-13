#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
source "${MODEL_DIR}/scripts/common.sh"
load_config
curl -fsS --max-time 15 "http://${BIND_ADDRESS}:${PORT}/v1/models" >/dev/null
printf '[DeepSeek IQ3_XXS] API is healthy\n'
