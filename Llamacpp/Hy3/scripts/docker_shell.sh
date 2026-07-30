#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
ensure_config
load_config

compose run --rm --no-deps --entrypoint /bin/bash hy3

