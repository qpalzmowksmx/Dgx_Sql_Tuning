#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
exec python3 ./sql_temperature_bench/dgx/run_sql_temperature_bench.py --profile hy3 "$@"
