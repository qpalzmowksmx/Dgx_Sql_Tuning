#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

BASE_URL="http://127.0.0.1:${PORT}/v1"

curl -fsS "${BASE_URL}/models"
echo

curl -fsS "${BASE_URL}/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'"${SERVED_MODEL_NAME}"'",
    "messages": [
      {
        "role": "user",
        "content": "Reply with exactly: OK"
      }
    ],
    "temperature": 0.0,
    "max_tokens": 64
  }'
echo
