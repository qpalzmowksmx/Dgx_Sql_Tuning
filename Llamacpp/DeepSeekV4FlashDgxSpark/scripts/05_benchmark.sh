#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

for name in FIT USE_MMAP DIRECT_IO GGML_CUDA_ENABLE_UNIFIED_MEMORY; do
  require_bool "${name}"
done

BENCH_BIN="${LLAMA_CPP_DIR}/build/bin/llama-bench"
if [[ ! -x "${BENCH_BIN}" ]]; then
  echo "Missing llama-bench: ${BENCH_BIN}" >&2
  exit 1
fi

mkdir -p "${MODEL_CACHE_DIR}"
export LLAMA_CACHE="${MODEL_CACHE_DIR}"
export CUDA_VISIBLE_DEVICES
configure_cuda_runtime

mmap_value=0
direct_io_value=0
if [[ "${USE_MMAP}" == "1" ]]; then mmap_value=1; fi
if [[ "${DIRECT_IO}" == "1" ]]; then direct_io_value=1; fi

fit_args=()
if [[ "${FIT}" == "1" ]]; then
  fit_args=(-fitt "${FIT_TARGET_MIB}" -fitc "${FIT_MIN_CTX}")
fi

echo "Benchmarking generation at depths ${BENCH_DEPTH}."
echo "Stop llama-server first; this run loads another full model instance."
echo "ref=${LLAMA_CPP_REF} mmap=${mmap_value} op_offload_min_batch=${GGML_OP_OFFLOAD_MIN_BATCH}"

exec "${BENCH_BIN}" \
  -hf "${HF_GGUF_MODEL_REF}" \
  -p "${BENCH_PROMPT_TOKENS}" \
  -n "${BENCH_GENERATION_TOKENS}" \
  -d "${BENCH_DEPTH}" \
  -r "${BENCH_REPETITIONS}" \
  -o "${BENCH_OUTPUT_FORMAT}" \
  -b "${BATCH_SIZE}" \
  -ub "${UBATCH_SIZE}" \
  -t "${THREADS}" \
  -ctk "${KV_CACHE_TYPE_K}" \
  -ctv "${KV_CACHE_TYPE_V}" \
  -ngl 999 \
  -sm "${SPLIT_MODE}" \
  -mg "${MAIN_GPU}" \
  -fa "${FLASH_ATTN}" \
  -mmp "${mmap_value}" \
  -dio "${direct_io_value}" \
  "${fit_args[@]}" \
  --progress
