#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

./scripts/01_preflight.sh native
./scripts/02_build_llama_cpp.sh
./scripts/06_verify_backend_ops.sh
exec ./scripts/03_start_server.sh

