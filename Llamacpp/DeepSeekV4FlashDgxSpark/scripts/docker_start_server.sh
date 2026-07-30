#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
ensure_config
load_config

compose up -d --no-build
echo "Container started. Check with ./scripts/docker_health_check.sh"

