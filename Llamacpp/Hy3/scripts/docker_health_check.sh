#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
exec ./scripts/05_health_check.sh

