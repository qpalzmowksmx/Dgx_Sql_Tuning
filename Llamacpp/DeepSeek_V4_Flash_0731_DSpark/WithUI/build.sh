#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

exec "${MODEL_DIR}/build.sh" "$@"
