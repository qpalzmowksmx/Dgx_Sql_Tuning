#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
source ./scripts/common.sh
load_config

base_url="http://127.0.0.1:${PORT}/v1"
curl -fsS "${base_url}/models" >/dev/null

echo "Testing server-default reasoning_effort=high (request override intentionally omitted)..."
response="$(curl -fsS "${base_url}/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{
    "model":"'"${SERVED_MODEL_NAME}"'",
    "messages":[{"role":"user","content":"Compare two Oracle SQL execution plans and explain which evidence is needed before choosing one. Think step by step."}],
    "temperature":0.9,
    "top_p":1.0,
    "seed":42,
    "max_tokens":512,
    "stream":false
  }')"
printf '%s\n' "${response}"

if ! printf '%s\n' "${response}" | grep -Eq '"reasoning_content"[[:space:]]*:[[:space:]]*"[^"}]+'; then
  echo "Reasoning smoke test failed: server default did not produce parsed reasoning_content." >&2
  exit 1
fi

echo "Reasoning smoke test passed: global reasoning_effort=high and Hy3 parser are active."
