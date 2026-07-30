#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

for name in FIT USE_MMAP DIRECT_IO GGML_CUDA_ENABLE_UNIFIED_MEMORY; do
  require_bool "${name}"
done

SERVER_BIN="${LLAMA_CPP_DIR}/build/bin/llama-server"
if [[ ! -x "${SERVER_BIN}" ]]; then
  echo "Missing llama-server: ${SERVER_BIN}" >&2
  exit 1
fi

mkdir -p "${MODEL_CACHE_DIR}"
export LLAMA_CACHE="${MODEL_CACHE_DIR}"
export CUDA_VISIBLE_DEVICES
configure_cuda_runtime

FIT_ARGS=(--fit off)
if [[ "${FIT}" == "1" ]]; then
  FIT_ARGS=(--fit on --fit-target "${FIT_TARGET_MIB}" --fit-ctx "${FIT_MIN_CTX}")
fi

MMAP_ARGS=(--no-mmap)
if [[ "${USE_MMAP}" == "1" ]]; then
  MMAP_ARGS=(--mmap)
fi

DIRECT_IO_ARGS=(--no-direct-io)
if [[ "${DIRECT_IO}" == "1" ]]; then
  DIRECT_IO_ARGS=(--direct-io)
fi

MODEL_ARGS=(-hf "${HF_GGUF_MODEL_REF}")
MODEL_LABEL="${HF_GGUF_MODEL_REF}"
if [[ -n "${GGUF_MODEL}" ]]; then
  if [[ ! -r "${GGUF_MODEL}" ]]; then
    echo "Local GGUF is not readable: ${GGUF_MODEL}" >&2
    exit 1
  fi
  MODEL_ARGS=(--model "${GGUF_MODEL}")
  MODEL_LABEL="${GGUF_MODEL}"
fi

EXTRA_ARGS=()
if [[ -n "${LLAMA_SERVER_EXTRA_ARGS}" ]]; then
  read -r -a EXTRA_ARGS <<< "${LLAMA_SERVER_EXTRA_ARGS}"
fi

echo "Starting ${MODEL_DISPLAY_NAME}:"
echo "  source commit: ${LLAMA_CPP_REF}"
echo "  model:         ${MODEL_LABEL}"
echo "  endpoint:      http://${HOST}:${PORT}/v1"
echo "  memory:        DGX Spark UMA, ngl=${N_GPU_LAYERS}, fit margin=${FIT_TARGET_MIB} MiB"
echo "  context/KV:    ${CTX_SIZE}, ${KV_CACHE_TYPE_K}/${KV_CACHE_TYPE_V}"
echo "  decode op offload minimum batch: ${GGML_OP_OFFLOAD_MIN_BATCH}"
echo "  sampling:      temp=${TEMPERATURE}, top-p=${TOP_P}, top-k=${TOP_K}, min-p=${MIN_P}, seed=${SEED}"

exec "${SERVER_BIN}" \
  "${MODEL_ARGS[@]}" \
  --alias "${SERVED_MODEL_NAME}" \
  --host "${HOST}" \
  --port "${PORT}" \
  --ctx-size "${CTX_SIZE}" \
  --n-gpu-layers "${N_GPU_LAYERS}" \
  --split-mode "${SPLIT_MODE}" \
  --main-gpu "${MAIN_GPU}" \
  "${FIT_ARGS[@]}" \
  --parallel "${PARALLEL}" \
  --batch-size "${BATCH_SIZE}" \
  --ubatch-size "${UBATCH_SIZE}" \
  --threads "${THREADS}" \
  --threads-batch "${THREADS_BATCH}" \
  --cache-type-k "${KV_CACHE_TYPE_K}" \
  --cache-type-v "${KV_CACHE_TYPE_V}" \
  --flash-attn "${FLASH_ATTN}" \
  --temp "${TEMPERATURE}" \
  --top-p "${TOP_P}" \
  --top-k "${TOP_K}" \
  --min-p "${MIN_P}" \
  --presence-penalty "${PRESENCE_PENALTY}" \
  --frequency-penalty "${FREQUENCY_PENALTY}" \
  --repeat-penalty "${REPETITION_PENALTY}" \
  --seed "${SEED}" \
  "${MMAP_ARGS[@]}" \
  "${DIRECT_IO_ARGS[@]}" \
  "${EXTRA_ARGS[@]}"
