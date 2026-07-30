#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONFIG_KEYS=(
  LLAMA_CPP_REPO LLAMA_CPP_BRANCH LLAMA_CPP_REF LLAMA_CPP_PRE_CUDA_REF
  LLAMA_CPP_BASE_REF CUDA_ARCHITECTURES
  GGML_CUDA_FA_ALL_QUANTS GGML_NATIVE CUDA_IMAGE HF_GGUF_MODEL_REF GGUF_MODEL
  MODEL_DISPLAY_NAME SERVED_MODEL_NAME WORK_DIR LLAMA_CPP_DIR MODEL_CACHE_DIR
  N_GPU_LAYERS SPLIT_MODE MAIN_GPU FIT FIT_TARGET_MIB FIT_MIN_CTX CTX_SIZE
  KV_CACHE_TYPE_K KV_CACHE_TYPE_V PARALLEL BATCH_SIZE UBATCH_SIZE THREADS
  THREADS_BATCH FLASH_ATTN USE_MMAP DIRECT_IO TEMPERATURE TOP_P TOP_K MIN_P
  PRESENCE_PENALTY FREQUENCY_PENALTY REPETITION_PENALTY SEED GGML_CUDA_ENABLE_UNIFIED_MEMORY
  GGML_OP_OFFLOAD_MIN_BATCH HOST BIND_ADDRESS PORT LLAMA_SERVER_EXTRA_ARGS
  MIN_SYSTEM_MEMORY_GIB MIN_FREE_DISK_GIB SKIP_PREFLIGHT ALLOW_UNSUPPORTED_HARDWARE
  GPU_NAME_PATTERN BENCH_PROMPT_TOKENS BENCH_GENERATION_TOKENS BENCH_DEPTH
  BENCH_REPETITIONS BENCH_OUTPUT_FORMAT BENCH_RESULTS_DIR DOCKER_IMAGE DOCKER_CONTAINER
  DOCKER_MODEL_CACHE_VOLUME RESTART_POLICY HF_TOKEN CUDA_VISIBLE_DEVICES LLAMA_CACHE
)

abs_path() {
  local path="$1"
  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s/%s\n' "${ROOT_DIR}" "${path}"
  fi
}

ensure_config() {
  if [[ ! -f "${ROOT_DIR}/config.env" ]]; then
    cp "${ROOT_DIR}/config.env.example" "${ROOT_DIR}/config.env"
    echo "Created ${ROOT_DIR}/config.env"
  fi
}

load_config() {
  local key index
  local -a override_names=()
  local -a override_values=()

  for key in "${CONFIG_KEYS[@]}"; do
    if printenv "${key}" >/dev/null 2>&1; then
      override_names+=("${key}")
      override_values+=("${!key}")
    fi
  done

  if [[ -f "${ROOT_DIR}/config.env" ]]; then
    set -a
    source "${ROOT_DIR}/config.env"
    set +a
  elif [[ -f "${ROOT_DIR}/config.env.example" ]]; then
    set -a
    source "${ROOT_DIR}/config.env.example"
    set +a
  fi

  for ((index = 0; index < ${#override_names[@]}; index++)); do
    key="${override_names[${index}]}"
    printf -v "${key}" '%s' "${override_values[${index}]}"
    export "${key}"
  done

  : "${LLAMA_CPP_REPO:=https://github.com/satindergrewal/llama.cpp.git}"
  : "${LLAMA_CPP_BRANCH:=deepseek-v4-flash}"
  : "${LLAMA_CPP_REF:=7a02824e968f2ce85ad919169962e0020595d141}"
  : "${LLAMA_CPP_PRE_CUDA_REF:=6652af2cb162936806e5ac47438c006937156b3f}"
  : "${LLAMA_CPP_BASE_REF:=8f114a9b573b69035299f9b924047f53c1e22c7e}"
  : "${CUDA_ARCHITECTURES:=121}"
  : "${GGML_CUDA_FA_ALL_QUANTS:=1}"
  : "${GGML_NATIVE:=1}"
  : "${CUDA_IMAGE:=nvcr.io/nvidia/cuda:13.0.1-devel-ubuntu24.04}"
  : "${HF_GGUF_MODEL_REF:=unsloth/DeepSeek-V4-Flash-GGUF:UD-IQ3_XXS}"
  : "${GGUF_MODEL:=}"
  : "${MODEL_DISPLAY_NAME:=DeepSeek V4 Flash UD-IQ3_XXS DGX Spark optimized fork}"
  : "${SERVED_MODEL_NAME:=deepseek-v4-flash-iq3-xxs}"
  : "${WORK_DIR:=runtime}"
  : "${LLAMA_CPP_DIR:=runtime/llama.cpp}"
  : "${MODEL_CACHE_DIR:=runtime/llama-cache}"
  : "${N_GPU_LAYERS:=auto}"
  : "${SPLIT_MODE:=none}"
  : "${MAIN_GPU:=0}"
  : "${FIT:=1}"
  : "${FIT_TARGET_MIB:=8192}"
  : "${FIT_MIN_CTX:=65536}"
  : "${CTX_SIZE:=65536}"
  : "${KV_CACHE_TYPE_K:=q8_0}"
  : "${KV_CACHE_TYPE_V:=q8_0}"
  : "${PARALLEL:=1}"
  : "${BATCH_SIZE:=1024}"
  : "${UBATCH_SIZE:=256}"
  : "${THREADS:=16}"
  : "${THREADS_BATCH:=20}"
  : "${FLASH_ATTN:=on}"
  : "${USE_MMAP:=0}"
  : "${DIRECT_IO:=0}"
  : "${TEMPERATURE:=0.20}"
  : "${TOP_P:=1.0}"
  : "${TOP_K:=0}"
  : "${MIN_P:=0.0}"
  : "${PRESENCE_PENALTY:=0.0}"
  : "${FREQUENCY_PENALTY:=0.0}"
  : "${REPETITION_PENALTY:=1.0}"
  : "${SEED:=42}"
  : "${GGML_CUDA_ENABLE_UNIFIED_MEMORY:=1}"
  : "${GGML_OP_OFFLOAD_MIN_BATCH:=32}"
  : "${HOST:=127.0.0.1}"
  : "${BIND_ADDRESS:=127.0.0.1}"
  : "${PORT:=8080}"
  : "${LLAMA_SERVER_EXTRA_ARGS:=--metrics --perf --jinja}"
  : "${MIN_SYSTEM_MEMORY_GIB:=115}"
  : "${MIN_FREE_DISK_GIB:=140}"
  : "${SKIP_PREFLIGHT:=0}"
  : "${ALLOW_UNSUPPORTED_HARDWARE:=0}"
  : "${GPU_NAME_PATTERN:=GB10}"
  : "${BENCH_PROMPT_TOKENS:=512}"
  : "${BENCH_GENERATION_TOKENS:=64}"
  : "${BENCH_DEPTH:=0,4096,8192,16384,32768}"
  : "${BENCH_REPETITIONS:=3}"
  : "${BENCH_OUTPUT_FORMAT:=md}"
  : "${BENCH_RESULTS_DIR:=logs/benchmarks}"
  : "${DOCKER_IMAGE:=llm-sql-dsv4-iq3xxs-dgx-spark:cuda13}"
  : "${DOCKER_CONTAINER:=llm-sql-dsv4-iq3xxs-dgx-spark}"
  : "${DOCKER_MODEL_CACHE_VOLUME:=llm-sql-dsv4-iq3xxs-dgx-spark-cache}"
  : "${RESTART_POLICY:=unless-stopped}"
  : "${HF_TOKEN:=}"
  : "${CUDA_VISIBLE_DEVICES:=0}"

  WORK_DIR="$(abs_path "${WORK_DIR}")"
  LLAMA_CPP_DIR="$(abs_path "${LLAMA_CPP_DIR}")"
  MODEL_CACHE_DIR="$(abs_path "${MODEL_CACHE_DIR}")"
  if [[ -n "${GGUF_MODEL}" ]]; then
    GGUF_MODEL="$(abs_path "${GGUF_MODEL}")"
  fi
  BENCH_RESULTS_DIR="$(abs_path "${BENCH_RESULTS_DIR}")"
  LLAMA_CACHE="${MODEL_CACHE_DIR}"

  export ROOT_DIR
  export "${CONFIG_KEYS[@]}"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing command: ${cmd}" >&2
    exit 1
  fi
}

require_bool() {
  local name="$1"
  local value="${!name}"
  if [[ "${value}" != "0" && "${value}" != "1" ]]; then
    echo "${name} must be 0 or 1, got: ${value}" >&2
    exit 2
  fi
}

require_positive_int() {
  local name="$1"
  local value="${!name}"
  if [[ ! "${value}" =~ ^[1-9][0-9]*$ ]]; then
    echo "${name} must be a positive integer, got: ${value}" >&2
    exit 2
  fi
}

configure_cuda_runtime() {
  require_bool GGML_CUDA_ENABLE_UNIFIED_MEMORY
  require_positive_int GGML_OP_OFFLOAD_MIN_BATCH

  if [[ "${GGML_CUDA_ENABLE_UNIFIED_MEMORY}" == "1" ]]; then
    export GGML_CUDA_ENABLE_UNIFIED_MEMORY=1
  else
    unset GGML_CUDA_ENABLE_UNIFIED_MEMORY
  fi
  export GGML_OP_OFFLOAD_MIN_BATCH
}

write_benchmark_metadata() {
  local output_file="$1"
  local benchmark_ref="$2"
  local mmap_mode="$3"
  local op_min_batch="$4"

  mkdir -p "$(dirname "${output_file}")"
  {
    printf 'timestamp_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'benchmark_ref=%s\n' "${benchmark_ref}"
    printf 'model=%s\n' "${HF_GGUF_MODEL_REF}"
    printf 'depths=%s\n' "${BENCH_DEPTH}"
    printf 'mmap=%s\n' "${mmap_mode}"
    printf 'ggml_op_offload_min_batch=%s\n' "${op_min_batch}"
    printf 'ggml_cuda_enable_unified_memory=%s\n' "${GGML_CUDA_ENABLE_UNIFIED_MEMORY}"
    printf 'context=%s\n' "${CTX_SIZE}"
    printf 'kv=%s/%s\n' "${KV_CACHE_TYPE_K}" "${KV_CACHE_TYPE_V}"
    printf 'batch=%s\n' "${BATCH_SIZE}"
    printf 'ubatch=%s\n' "${UBATCH_SIZE}"
    printf 'threads=%s\n' "${THREADS}"
    printf 'uname=%s\n' "$(uname -a)"
    if command -v nvidia-smi >/dev/null 2>&1; then
      printf '%s\n' '--- nvidia-smi ---'
      nvidia-smi || true
    fi
    if command -v nvpmodel >/dev/null 2>&1; then
      printf '%s\n' '--- nvpmodel ---'
      nvpmodel -q || true
    fi
    if command -v nvcc >/dev/null 2>&1; then
      printf '%s\n' '--- nvcc ---'
      nvcc --version || true
    fi
  } > "${output_file}"
}

compose() {
  docker compose \
    --env-file "${ROOT_DIR}/config.env" \
    -f "${ROOT_DIR}/docker-compose.yml" \
    "$@"
}
