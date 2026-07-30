#!/usr/bin/env bash
set -euo pipefail

: "${REASONING_EFFORT:=high}"
if [[ "${REASONING_EFFORT}" != "high" ]]; then
  echo "Reasoning profile requires REASONING_EFFORT=high, got: ${REASONING_EFFORT}" >&2
  exit 2
fi

# llama-server applies this object to every request before request-specific
# chat_template_kwargs. Hy3's embedded template uses it to emit the thinking
# prefix. The pinned parser patch returns that block as reasoning_content.
export LLAMA_ARG_CHAT_TEMPLATE_KWARGS='{"reasoning_effort":"high"}'

echo "Hy3 reasoning profile: default chat_template_kwargs=${LLAMA_ARG_CHAT_TEMPLATE_KWARGS}"
exec "$(dirname "$0")/04_start_server.sh"
