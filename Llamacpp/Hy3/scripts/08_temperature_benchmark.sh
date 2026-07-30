#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
exec python3 ./temperature_bench/temperature_bench.py --profile hy3 "$@"
