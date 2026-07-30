#!/usr/bin/env bash
set -euo pipefail

MODEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLAMACPP_DIR="$(cd "${MODEL_DIR}/.." && pwd)"
cd "${MODEL_DIR}"

if [[ ! -f config.env ]]; then
  cp config.env.example config.env
  echo "Created ${MODEL_DIR}/config.env from config.env.example"
fi
if [[ ! -f Reasoning-config.env ]]; then
  cp Reasoning-config.env.example Reasoning-config.env
  echo "Created ${MODEL_DIR}/Reasoning-config.env from Reasoning-config.env.example"
fi

set -a
source config.env
source Reasoning-config.env
set +a
IMAGE_NAME="${DOCKER_IMAGE:-llm-sql-hy3-iq1m-mtp-dgx-spark:cuda13}"

if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
  echo "[Hy3 Reasoning] required offline image is missing: ${IMAGE_NAME}" >&2
  echo "[Hy3 Reasoning] build it while online or set DOCKER_IMAGE to the loaded Hy3 image." >&2
  exit 1
fi

"${LLAMACPP_DIR}/modelctl.sh" stop
docker compose \
  --env-file config.env \
  --env-file Reasoning-config.env \
  -f Reasoning-docker-compose.yml \
  down --remove-orphans >/dev/null 2>&1 || true

docker compose \
  --env-file config.env \
  --env-file Reasoning-config.env \
  -f Reasoning-docker-compose.yml \
  up -d --no-build --pull never --remove-orphans

"${LLAMACPP_DIR}/offline_proxy.sh" start \
  "${DOCKER_CONTAINER:-llm-sql-hy3-iq1m-mtp-reasoning-high}" "${PORT:-8080}" "${PORT:-8080}"
