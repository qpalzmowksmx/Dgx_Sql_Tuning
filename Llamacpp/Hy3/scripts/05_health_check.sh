#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

base_url="http://127.0.0.1:${PORT}/v1"

curl -fsS "${base_url}/models"
echo

chat_response="$(curl -fsS "${base_url}/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{
    "model":"'"${SERVED_MODEL_NAME}"'",
    "messages":[{"role":"user","content":"Reply with exactly: OK"}],
    "chat_template_kwargs":{"reasoning_effort":"no_think"},
    "temperature":0,
    "max_tokens":64,
    "stream":false
  }')"
printf '%s\n' "${chat_response}"

if ! printf '%s\n' "${chat_response}" | grep -Eq '"content"[[:space:]]*:[[:space:]]*"OK"'; then
  echo "Health check failed: the model did not reply with exactly OK." >&2
  exit 1
fi

echo "Health check passed: model listing and exact generation response are healthy."
