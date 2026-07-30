#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
ensure_config
load_config

compose run --rm --no-deps \
  --entrypoint /opt/hy3-wrapper/scripts/06_model_manifest.sh hy3
