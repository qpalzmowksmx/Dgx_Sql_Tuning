#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

for name in FIT USE_MMAP DIRECT_IO ENABLE_MTP \
  GGML_CUDA_ENABLE_UNIFIED_MEMORY; do
  require_bool "${name}"
done

SERVER_BIN="${LLAMA_CPP_DIR}/build/bin/llama-server"
if [[ ! -x "${SERVER_BIN}" ]]; then
  echo "Missing llama-server: ${SERVER_BIN}" >&2
  exit 1
fi
if [[ ! -f "${MODEL_PATH}" ]]; then
  echo "Missing model: ${MODEL_PATH}" >&2
  echo "Run ./scripts/03_download_model.sh first." >&2
  exit 1
fi
actual_size="$(file_size "${MODEL_PATH}")"
if [[ "${actual_size}" != "${MODEL_SIZE_BYTES}" ]]; then
  echo "Model size mismatch: expected ${MODEL_SIZE_BYTES}, found ${actual_size}." >&2
  exit 1
fi

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

MTP_ARGS=(--spec-type none)
if [[ "${ENABLE_MTP}" == "1" ]]; then
  MTP_ARGS=(
    --spec-type draft-mtp
    --spec-draft-n-max "${SPEC_DRAFT_N_MAX}"
    --spec-draft-n-min "${SPEC_DRAFT_N_MIN}"
    --spec-draft-p-min "${SPEC_DRAFT_P_MIN}"
    --cache-type-k-draft "${KV_CACHE_TYPE_K_DRAFT}"
    --cache-type-v-draft "${KV_CACHE_TYPE_V_DRAFT}"
  )
fi

EXTRA_ARGS=()
if [[ -n "${LLAMA_SERVER_EXTRA_ARGS}" ]]; then
  read -r -a EXTRA_ARGS <<< "${LLAMA_SERVER_EXTRA_ARGS}"
fi

echo "Starting ${MODEL_DISPLAY_NAME}:"
echo "  llama.cpp: ${LLAMA_CPP_REF} + pinned official Hy3 arch/MTP/parser patches"
echo "  model:     ${MODEL_PATH}"
echo "  endpoint:  http://${HOST}:${PORT}/v1"
echo "  context:   ${CTX_SIZE}, main KV ${KV_CACHE_TYPE_K}/${KV_CACHE_TYPE_V}"
echo "  MTP:       ${ENABLE_MTP}, n=${SPEC_DRAFT_N_MIN}..${SPEC_DRAFT_N_MAX}, p-min=${SPEC_DRAFT_P_MIN}"
echo "  sampling:  temp=${TEMPERATURE}, top-p=${TOP_P}, top-k=${TOP_K}, min-p=${MIN_P}, seed=${SEED}"

exec "${SERVER_BIN}" \
  --model "${MODEL_PATH}" \
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
  "${MTP_ARGS[@]}" \
  "${MMAP_ARGS[@]}" \
  "${DIRECT_IO_ARGS[@]}" \
  "${EXTRA_ARGS[@]}"
