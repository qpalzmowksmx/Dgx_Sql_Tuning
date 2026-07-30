#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
exec ./scripts/07_smoke_test.sh
