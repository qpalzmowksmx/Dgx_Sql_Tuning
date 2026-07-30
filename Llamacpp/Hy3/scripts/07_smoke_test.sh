#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

./scripts/05_health_check.sh

base_url="http://127.0.0.1:${PORT}/v1"

echo "Testing the pinned Hy3 reasoning parser..."
reasoning_response="$(curl -fsS "${base_url}/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{
    "model":"'"${SERVED_MODEL_NAME}"'",
    "messages":[{"role":"user","content":"Calculate 17 multiplied by 19. Think first, then give the final number."}],
    "chat_template_kwargs":{"reasoning_effort":"high"},
    "temperature":0,
    "max_tokens":256,
    "stream":false
  }')"
printf '%s\n' "${reasoning_response}"
if ! printf '%s\n' "${reasoning_response}" | grep -Eq '"reasoning_content"[[:space:]]*:[[:space:]]*"[^"}]+'; then
  echo "Smoke test failed: no non-empty reasoning_content field was parsed." >&2
  exit 1
fi

echo "Testing the pinned Hy3 tool-call parser..."
tool_response="$(curl -fsS "${base_url}/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{
    "model":"'"${SERVED_MODEL_NAME}"'",
    "messages":[{"role":"user","content":"Call lookup_sql_dialect exactly once for Oracle."}],
    "chat_template_kwargs":{"reasoning_effort":"no_think"},
    "tools":[{
      "type":"function",
      "function":{
        "name":"lookup_sql_dialect",
        "description":"Look up SQL dialect metadata for one database vendor.",
        "parameters":{
          "type":"object",
          "properties":{"vendor":{"type":"string","enum":["oracle"]}},
          "required":["vendor"],
          "additionalProperties":false
        }
      }
    }],
    "tool_choice":"required",
    "parallel_tool_calls":false,
    "temperature":0,
    "max_tokens":256,
    "stream":false
  }')"
printf '%s\n' "${tool_response}"
if ! printf '%s\n' "${tool_response}" | grep -Eq '"tool_calls"' || \
   ! printf '%s\n' "${tool_response}" | grep -Eq 'lookup_sql_dialect' || \
   ! printf '%s\n' "${tool_response}" | grep -Eq 'oracle'; then
  echo "Smoke test failed: the expected Oracle lookup tool call was not parsed." >&2
  exit 1
fi

echo "Smoke test passed: generation, reasoning parsing, and tool-call parsing are healthy."
