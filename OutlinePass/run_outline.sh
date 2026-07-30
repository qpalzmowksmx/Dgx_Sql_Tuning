#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

SQL_FILE="${1:-../Query/Query_by_qwen.sql}"
OUT_DIR="${2:-${OUTLINE_OUTPUT_DIR:-runtime/outlines}}"

exec python3 scripts/run_outline.py \
  --sql "${SQL_FILE}" \
  --out-dir "${OUT_DIR}"

