#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
ensure_config
load_config

./scripts/01_preflight.sh docker
compose build
compose up -d --no-build
echo "Hy3 service is building/downloading/starting in the background."
echo "Follow progress with ./scripts/docker_logs.sh"
echo "Check readiness with ./scripts/docker_health_check.sh"

