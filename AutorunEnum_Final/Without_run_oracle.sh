#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Legacy Oracle path: Qwen -> critics, with no critic-feedback rewrite.
exec "${SCRIPT_DIR}/_run_oracle_pipeline.sh" 0 without-ui
