#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

SERVER_BIN="${LLAMA_CPP_DIR}/build/bin/llama-server"

if [[ ! -x "${SERVER_BIN}" ]]; then
  echo "Missing llama-server binary: ${SERVER_BIN}" >&2
  exit 1
fi

FLASH_ARGS=()
case "${FLASH_ATTN,,}" in
  1|on|true|yes)  FLASH_ARGS+=(--flash-attn on) ;;
  0|off|false|no) FLASH_ARGS+=(--flash-attn off) ;;
  auto)           FLASH_ARGS+=(--flash-attn auto) ;;
  *)
    echo "Invalid FLASH_ATTN=${FLASH_ATTN}; use on, off, auto, 1, or 0." >&2
    exit 1
    ;;
esac

MODEL_ARGS=()
MODEL_LABEL=""
if [[ -n "${HF_GGUF_MODEL_REF}" ]]; then
  MODEL_ARGS=(-hf "${HF_GGUF_MODEL_REF}")
  MODEL_LABEL="${HF_GGUF_MODEL_REF}"
else
  if [[ ! -f "${GGUF_MODEL}" ]]; then
    echo "Missing GGUF model: ${GGUF_MODEL}" >&2
    echo "Run ./scripts/03_download_model.sh and ./scripts/04_convert_gguf.sh first." >&2
    exit 1
  fi
  MODEL_ARGS=(--model "${GGUF_MODEL}")
  MODEL_LABEL="${GGUF_MODEL}"
fi

EXTRA_ARGS=()
if [[ -n "${LLAMA_SERVER_EXTRA_ARGS}" ]]; then
  read -r -a EXTRA_ARGS <<< "${LLAMA_SERVER_EXTRA_ARGS}"
fi

echo "Starting llama-server:"
echo "  name:  ${MODEL_DISPLAY_NAME}"
echo "  model: ${MODEL_LABEL}"
echo "  url:   http://${HOST}:${PORT}/v1"
echo "  ctx:   ${CTX_SIZE}"
echo "  kv:    k=${KV_CACHE_TYPE_K}, v=${KV_CACHE_TYPE_V}"
echo "  sampling: temp=${TEMPERATURE}, top-p=${TOP_P}, top-k=${TOP_K}, min-p=${MIN_P}, seed=${SEED}"

exec "${SERVER_BIN}" \
  "${MODEL_ARGS[@]}" \
  --alias "${SERVED_MODEL_NAME}" \
  --host "${HOST}" \
  --port "${PORT}" \
  --ctx-size "${CTX_SIZE}" \
  --n-gpu-layers "${N_GPU_LAYERS}" \
  --parallel "${PARALLEL}" \
  --batch-size "${BATCH_SIZE}" \
  --ubatch-size "${UBATCH_SIZE}" \
  --threads "${THREADS}" \
  --cache-type-k "${KV_CACHE_TYPE_K}" \
  --cache-type-v "${KV_CACHE_TYPE_V}" \
  --temp "${TEMPERATURE}" \
  --top-p "${TOP_P}" \
  --top-k "${TOP_K}" \
  --min-p "${MIN_P}" \
  --presence-penalty "${PRESENCE_PENALTY}" \
  --frequency-penalty "${FREQUENCY_PENALTY}" \
  --repeat-penalty "${REPETITION_PENALTY}" \
  --seed "${SEED}" \
  --jinja \
  "${FLASH_ARGS[@]}" \
  "${EXTRA_ARGS[@]}"
