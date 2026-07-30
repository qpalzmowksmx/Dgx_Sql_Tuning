#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
ensure_config
load_config

./scripts/01_preflight.sh docker
compose build
compose run --rm --no-deps --entrypoint /opt/dsv4-dgx-wrapper/scripts/06_verify_backend_ops.sh \
  deepseek-v4-flash-dgx-spark
