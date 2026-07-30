#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
ensure_config
load_config

require_cmd tee
mkdir -p "${BENCH_RESULTS_DIR}"
manifest_file="${BENCH_RESULTS_DIR}/model-sha256-$(date -u +%Y%m%dT%H%M%SZ).txt"

if compose ps --status running --services | grep -q '^deepseek-v4-flash-dgx-spark$'; then
  echo "Stop the running server before hashing the 103 GB model cache." >&2
  exit 1
fi

compose build
compose run --rm --no-deps -T \
  --entrypoint /opt/dsv4-dgx-wrapper/scripts/08_model_manifest.sh \
  deepseek-v4-flash-dgx-spark | tee "${manifest_file}"

echo "Model manifest written to ${manifest_file}"
