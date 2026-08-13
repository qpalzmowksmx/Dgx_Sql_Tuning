#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

CONFIG_KEYS=(
  LLAMA_CPP_REPO LLAMA_CPP_BRANCH LLAMA_CPP_REF CUDA_IMAGE CUDA_ARCHITECTURES
  GGML_CUDA_FA_ALL_QUANTS GGML_NATIVE LOCAL_GGUF_RELATIVE_DIR LOCAL_GGUF_DIR
  GGUF_MODEL OFFLINE_MODEL_REQUIRED EXPECTED_MODEL_MARKER HF_GGUF_MODEL_REF
  MODEL_DISPLAY_NAME SERVED_MODEL_NAME MODEL_CACHE_DIR CTX_SIZE FIT
  FIT_TARGET_MIB FIT_MIN_CTX KV_CACHE_TYPE_K KV_CACHE_TYPE_V N_GPU_LAYERS
  SPLIT_MODE MAIN_GPU PARALLEL BATCH_SIZE UBATCH_SIZE THREADS THREADS_BATCH
  FLASH_ATTN USE_MMAP DIRECT_IO TEMPERATURE TOP_P TOP_K MIN_P
  PRESENCE_PENALTY FREQUENCY_PENALTY REPETITION_PENALTY SEED THINKING_MODE
  REASONING_EFFORT MAX_TOKENS GGML_CUDA_ENABLE_UNIFIED_MEMORY
  GGML_OP_OFFLOAD_MIN_BATCH HOST BIND_ADDRESS PORT LLAMA_SERVER_EXTRA_ARGS
  DOCKER_IMAGE LEGACY_DOCKER_IMAGE DOCKER_CONTAINER DOCKER_MODEL_CACHE_VOLUME
  DOCKER_HF_CACHE_VOLUME RESTART_POLICY SHM_SIZE HF_TOKEN BUILD_ON_START
  MODEL_HEALTH_TIMEOUT_SEC OPEN_WEBUI_HEALTH_TIMEOUT_SEC OPEN_WEBUI_IMAGE
  OPEN_WEBUI_CONTAINER OPEN_WEBUI_DATA_VOLUME OPEN_WEBUI_NAME
  OPEN_WEBUI_BIND_ADDRESS OPEN_WEBUI_PORT OPENAI_API_KEY
)

abs_path() {
  if [[ "$1" = /* ]]; then printf '%s\n' "$1"; else printf '%s/%s\n' "${ROOT_DIR}" "$1"; fi
}

ensure_config() {
  if [[ ! -f "${ROOT_DIR}/config.env" ]]; then
    if [[ -f "${ROOT_DIR}/config.env.example" ]]; then
      cp "${ROOT_DIR}/config.env.example" "${ROOT_DIR}/config.env"
      printf '[DeepSeek IQ3_XXS] created %s\n' "${ROOT_DIR}/config.env"
    fi
  fi
}

load_config() {
  local key index
  local -a names=() values=()
  for key in "${CONFIG_KEYS[@]}"; do
    if printenv "${key}" >/dev/null 2>&1; then names+=("${key}"); values+=("${!key}"); fi
  done
  ensure_config
  if [[ -f "${ROOT_DIR}/config.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${ROOT_DIR}/config.env"
    set +a
  fi
  for ((index=0; index<${#names[@]}; index++)); do
    printf -v "${names[index]}" '%s' "${values[index]}"
    export "${names[index]}"
  done

  : "${EXPECTED_MODEL_MARKER:=UD-IQ3_XXS}"
  : "${HF_GGUF_MODEL_REF:=unsloth/DeepSeek-V4-Flash-0731-GGUF:UD-IQ3_XXS}"
  : "${LOCAL_GGUF_RELATIVE_DIR:=runtime/local-gguf}"
  : "${LOCAL_GGUF_DIR:=}"
  : "${GGUF_MODEL:=}"
  : "${OFFLINE_MODEL_REQUIRED:=1}"
  : "${MODEL_DISPLAY_NAME:=DeepSeek V4 Flash 0731 UD-IQ3_XXS}"
  : "${SERVED_MODEL_NAME:=deepseek-v4-flash-0731-iq3-xxs}"
  : "${MODEL_CACHE_DIR:=runtime/llama-cache}"
  : "${CTX_SIZE:=65536}"; : "${FIT:=1}"; : "${FIT_TARGET_MIB:=6144}"; : "${FIT_MIN_CTX:=32768}"
  : "${KV_CACHE_TYPE_K:=q8_0}"; : "${KV_CACHE_TYPE_V:=q8_0}"
  : "${N_GPU_LAYERS:=auto}"; : "${SPLIT_MODE:=none}"; : "${MAIN_GPU:=0}"; : "${PARALLEL:=1}"
  : "${BATCH_SIZE:=512}"; : "${UBATCH_SIZE:=128}"; : "${THREADS:=16}"; : "${THREADS_BATCH:=20}"
  : "${FLASH_ATTN:=on}"; : "${USE_MMAP:=0}"; : "${DIRECT_IO:=0}"
  : "${TEMPERATURE:=1.0}"; : "${TOP_P:=0.95}"; : "${TOP_K:=0}"; : "${MIN_P:=0.0}"
  : "${PRESENCE_PENALTY:=0.0}"; : "${FREQUENCY_PENALTY:=0.0}"; : "${REPETITION_PENALTY:=1.0}"
  : "${SEED:=42}"; : "${THINKING_MODE:=thinking}"; : "${REASONING_EFFORT:=max}"; : "${MAX_TOKENS:=16384}"
  : "${GGML_CUDA_ENABLE_UNIFIED_MEMORY:=1}"; : "${GGML_OP_OFFLOAD_MIN_BATCH:=32}"
  : "${HOST:=127.0.0.1}"; : "${BIND_ADDRESS:=127.0.0.1}"; : "${PORT:=8080}"
  : "${LLAMA_SERVER_EXTRA_ARGS:=--metrics --perf --jinja}"
  : "${DOCKER_IMAGE:=llm-sql-dsv4-0731-iq3xxs-dgx-spark:cuda13}"
  : "${LEGACY_DOCKER_IMAGE:=llm-sql-dsv4-0731-iq3s-dgx-spark:cuda13}"
  : "${DOCKER_CONTAINER:=llm-sql-dsv4-0731-iq3xxs-dgx-spark}"
  : "${DOCKER_MODEL_CACHE_VOLUME:=llm-sql-dsv4-0731-iq3xxs-dgx-spark-cache}"
  : "${DOCKER_HF_CACHE_VOLUME:=llm-sql-dsv4-0731-iq3xxs-dgx-spark-hf-cache}"
  : "${RESTART_POLICY:=unless-stopped}"; : "${SHM_SIZE:=16gb}"; : "${HF_TOKEN:=}"
  : "${BUILD_ON_START:=0}"; : "${MODEL_HEALTH_TIMEOUT_SEC:=7200}"; : "${OPEN_WEBUI_HEALTH_TIMEOUT_SEC:=900}"
  : "${OPEN_WEBUI_IMAGE:=llm-sql-open-webui:v0.9.4-dgx-stats}"
  : "${OPEN_WEBUI_CONTAINER:=deepseek-v4-flash-0731-iq3xxs-open-webui}"
  : "${OPEN_WEBUI_DATA_VOLUME:=deepseek-v4-flash-0731-iq3xxs-general-webui-data}"
  : "${OPEN_WEBUI_NAME:=DeepSeek V4 Flash 0731 UD-IQ3_XXS}"
  : "${OPEN_WEBUI_BIND_ADDRESS:=127.0.0.1}"; : "${OPEN_WEBUI_PORT:=3000}"; : "${OPENAI_API_KEY:=sk-local}"

  MODEL_CACHE_DIR="$(abs_path "${MODEL_CACHE_DIR}")"
  export ROOT_DIR MODEL_CACHE_DIR
  export "${CONFIG_KEYS[@]}"
}

require_bool() {
  local value="${!1}"
  [[ "${value}" = 0 || "${value}" = 1 ]] || { printf '%s must be 0 or 1\n' "$1" >&2; return 2; }
}

configure_cuda_runtime() {
  require_bool GGML_CUDA_ENABLE_UNIFIED_MEMORY
  if [[ "${GGML_CUDA_ENABLE_UNIFIED_MEMORY}" = 1 ]]; then
    export GGML_CUDA_ENABLE_UNIFIED_MEMORY=1
  else
    unset GGML_CUDA_ENABLE_UNIFIED_MEMORY
  fi
  export GGML_OP_OFFLOAD_MIN_BATCH
}
