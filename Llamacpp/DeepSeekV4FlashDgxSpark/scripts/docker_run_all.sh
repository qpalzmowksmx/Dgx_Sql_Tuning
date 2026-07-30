#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
ensure_config
load_config

./scripts/01_preflight.sh docker
echo "Starting attached. First use builds SM121 llama.cpp and downloads about 103 GB."
echo "Press Ctrl+C for a graceful stop; the named model-cache volume is retained."
compose build
compose run --rm --no-deps --entrypoint /opt/dsv4-dgx-wrapper/scripts/06_verify_backend_ops.sh \
  deepseek-v4-flash-dgx-spark
compose up --no-build
