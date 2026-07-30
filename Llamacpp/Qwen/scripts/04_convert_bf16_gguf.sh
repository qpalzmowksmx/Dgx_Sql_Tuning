#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
exec ./scripts/04_convert_gguf.sh
