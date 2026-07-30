#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Same no-retune Oracle path, then leave Qwen and Open WebUI running for review.
exec "${SCRIPT_DIR}/_run_oracle_pipeline.sh" 0 with-ui
