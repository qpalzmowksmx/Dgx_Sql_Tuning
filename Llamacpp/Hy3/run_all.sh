#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

./scripts/01_preflight.sh native
./scripts/02_build_llama_cpp.sh
./scripts/03_download_model.sh
exec ./scripts/04_start_server.sh

