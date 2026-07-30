#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
ensure_config
load_config

./scripts/01_preflight.sh docker
echo "Starting attached. First use builds SM121-real llama.cpp and downloads 91.76 GB."
echo "The downloader resumes interrupted transfers and verifies the pinned SHA-256."
echo "Press Ctrl+C for a graceful stop; the named model volume is retained."
compose build
compose up --no-build
