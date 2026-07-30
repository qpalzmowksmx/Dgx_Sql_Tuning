#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f config.env ]]; then
  echo "config.env not found. Creating it from config.env.example."
  cp config.env.example config.env
fi

docker compose --env-file config.env up --build
