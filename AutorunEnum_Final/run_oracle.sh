#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default Oracle path: Qwen draft -> Hy3 critique -> DeepSeek 0731 rewrite -> Hy3 review.
exec "${SCRIPT_DIR}/_run_oracle_pipeline.sh" "${CRITIC_RETUNE_ROUNDS:-1}" without-ui
