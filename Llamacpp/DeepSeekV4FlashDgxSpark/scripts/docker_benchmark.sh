#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
ensure_config
load_config

if compose ps --status running --services | grep -q '^deepseek-v4-flash-dgx-spark$'; then
  echo "Stop the running server first: docker compose --env-file config.env down" >&2
  exit 1
fi

./scripts/01_preflight.sh docker
compose build
compose run --rm --no-deps -T --entrypoint /opt/dsv4-dgx-wrapper/scripts/06_verify_backend_ops.sh \
  deepseek-v4-flash-dgx-spark
compose run --rm --no-deps -T --entrypoint /opt/dsv4-dgx-wrapper/scripts/05_benchmark.sh \
  deepseek-v4-flash-dgx-spark
