#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

args=(docker compose -f Reasoning-docker-compose.yml)
[[ -f config.env ]] && args+=(--env-file config.env)
[[ -f Reasoning-config.env ]] && args+=(--env-file Reasoning-config.env)
exec "${args[@]}" down --remove-orphans
