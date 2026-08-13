#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "$0")/.."
source ./scripts/common.sh
source ./scripts/local_model.sh
load_config
prepare_runtime_local_model "${ROOT_DIR}"

for name in FIT USE_MMAP DIRECT_IO GGML_CUDA_ENABLE_UNIFIED_MEMORY OFFLINE_MODEL_REQUIRED; do require_bool "${name}"; done

SERVER_BIN="/opt/llama.cpp/build/bin/llama-server"
[[ -x "${SERVER_BIN}" ]] || { printf 'Missing llama-server: %s\n' "${SERVER_BIN}" >&2; exit 1; }
mkdir -p "${MODEL_CACHE_DIR}"
export LLAMA_CACHE="${MODEL_CACHE_DIR}"
configure_cuda_runtime

fit_args=(--fit off); [[ "${FIT}" = 1 ]] && fit_args=(--fit on --fit-target "${FIT_TARGET_MIB}" --fit-ctx "${FIT_MIN_CTX}")
mmap_args=(--no-mmap); [[ "${USE_MMAP}" = 1 ]] && mmap_args=(--mmap)
direct_args=(--no-direct-io); [[ "${DIRECT_IO}" = 1 ]] && direct_args=(--direct-io)
model_args=(-hf "${HF_GGUF_MODEL_REF}"); [[ -n "${GGUF_MODEL}" ]] && model_args=(--model "${GGUF_MODEL}")
extra_args=(); [[ -n "${LLAMA_SERVER_EXTRA_ARGS}" ]] && read -r -a extra_args <<< "${LLAMA_SERVER_EXTRA_ARGS}"

case "${THINKING_MODE}" in thinking|non-thinking) ;; *) printf 'Invalid THINKING_MODE: %s\n' "${THINKING_MODE}" >&2; exit 2 ;; esac
case "${REASONING_EFFORT}" in low|medium|high|max) ;; *) printf 'Invalid REASONING_EFFORT: %s\n' "${REASONING_EFFORT}" >&2; exit 2 ;; esac
printf -v template_kwargs '{"thinking_mode":"%s","reasoning_effort":"%s"}' "${THINKING_MODE}" "${REASONING_EFFORT}"

printf '[DeepSeek IQ3_XXS] starting model=%s ctx=%s KV=%s/%s\n' "${GGUF_MODEL:-${HF_GGUF_MODEL_REF}}" "${CTX_SIZE}" "${KV_CACHE_TYPE_K}" "${KV_CACHE_TYPE_V}"
exec "${SERVER_BIN}" \
  "${model_args[@]}" --alias "${SERVED_MODEL_NAME}" --host "${HOST}" --port "${PORT}" \
  --n-predict "${MAX_TOKENS}" \
  --ctx-size "${CTX_SIZE}" --n-gpu-layers "${N_GPU_LAYERS}" --split-mode "${SPLIT_MODE}" --main-gpu "${MAIN_GPU}" \
  "${fit_args[@]}" --parallel "${PARALLEL}" --batch-size "${BATCH_SIZE}" --ubatch-size "${UBATCH_SIZE}" \
  --threads "${THREADS}" --threads-batch "${THREADS_BATCH}" --cache-type-k "${KV_CACHE_TYPE_K}" \
  --cache-type-v "${KV_CACHE_TYPE_V}" --flash-attn "${FLASH_ATTN}" --temp "${TEMPERATURE}" \
  --top-p "${TOP_P}" --top-k "${TOP_K}" --min-p "${MIN_P}" --presence-penalty "${PRESENCE_PENALTY}" \
  --frequency-penalty "${FREQUENCY_PENALTY}" --repeat-penalty "${REPETITION_PENALTY}" --seed "${SEED}" \
  --chat-template-kwargs "${template_kwargs}" "${mmap_args[@]}" "${direct_args[@]}" "${extra_args[@]}"
