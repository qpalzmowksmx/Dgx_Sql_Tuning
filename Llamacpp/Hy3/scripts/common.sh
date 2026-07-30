#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONFIG_KEYS=(
  LLAMA_CPP_REPO LLAMA_CPP_BRANCH LLAMA_CPP_REF HY3_PATCH_BASE_URL
  HY3_PATCH_01_FILE HY3_PATCH_01_SHA256 HY3_PATCH_02_FILE HY3_PATCH_02_SHA256 CUDA_ARCHITECTURES
  GGML_CUDA_FA_ALL_QUANTS GGML_NATIVE CUDA_IMAGE MODEL_REPO MODEL_REVISION
  MODEL_FILE MODEL_SIZE_BYTES MODEL_SHA256 MODEL_DISPLAY_NAME SERVED_MODEL_NAME
  WORK_DIR LLAMA_CPP_DIR MODEL_DIR N_GPU_LAYERS SPLIT_MODE MAIN_GPU FIT
  FIT_TARGET_MIB FIT_MIN_CTX CTX_SIZE KV_CACHE_TYPE_K KV_CACHE_TYPE_V
  KV_CACHE_TYPE_K_DRAFT KV_CACHE_TYPE_V_DRAFT PARALLEL BATCH_SIZE UBATCH_SIZE
  THREADS THREADS_BATCH FLASH_ATTN USE_MMAP DIRECT_IO ENABLE_MTP
  SPEC_DRAFT_N_MAX SPEC_DRAFT_N_MIN SPEC_DRAFT_P_MIN TEMPERATURE TOP_P TOP_K MIN_P
  PRESENCE_PENALTY FREQUENCY_PENALTY REPETITION_PENALTY SEED
  GGML_CUDA_ENABLE_UNIFIED_MEMORY GGML_OP_OFFLOAD_MIN_BATCH HOST BIND_ADDRESS
  PORT LLAMA_SERVER_EXTRA_ARGS MIN_SYSTEM_MEMORY_GIB MIN_RECLAIMABLE_MEMORY_GIB
  MIN_FREE_DISK_GIB MIN_POST_DOWNLOAD_FREE_GIB SKIP_PREFLIGHT
  ALLOW_UNSUPPORTED_HARDWARE GPU_NAME_PATTERN DOCKER_IMAGE
  DOCKER_CONTAINER DOCKER_MODEL_VOLUME RESTART_POLICY HF_TOKEN
  CUDA_VISIBLE_DEVICES MODEL_PATH MODEL_PARTIAL_PATH MODEL_MARKER_PATH
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

  : "${LLAMA_CPP_REPO:=https://github.com/ggml-org/llama.cpp.git}"
  : "${LLAMA_CPP_BRANCH:=master}"
  : "${LLAMA_CPP_REF:=19bba67c1f4db723c60a0d421aa0788bf4ddc699}"
  : "${HY3_PATCH_BASE_URL:=https://huggingface.co/AngelSlim/Hy3-GGUF/raw/218c93f0fb5227553b67e556b01dfe70fb70cf30/patches}"
  : "${HY3_PATCH_01_FILE:=01-hyv3-arch.patch}"
  : "${HY3_PATCH_01_SHA256:=23d9def340b452a4bad4900ed20f81d6fdfaf2954b91eae30cf1a0dd0daa21ca}"
  : "${HY3_PATCH_02_FILE:=02-hyv3-mtp-tools.patch}"
  : "${HY3_PATCH_02_SHA256:=51dea330aa41548d13c21535a7e5e0227f9ae3a182fc5e3cc241adee5ed8b0f7}"
  : "${CUDA_ARCHITECTURES:=121-real}"
  : "${GGML_CUDA_FA_ALL_QUANTS:=1}"
  : "${GGML_NATIVE:=1}"
  : "${CUDA_IMAGE:=nvcr.io/nvidia/cuda:13.0.1-devel-ubuntu24.04}"
  : "${MODEL_REPO:=AngelSlim/Hy3-GGUF}"
  : "${MODEL_REVISION:=218c93f0fb5227553b67e556b01dfe70fb70cf30}"
  : "${MODEL_FILE:=Hy3-IQ1_M-mtp.gguf}"
  : "${MODEL_SIZE_BYTES:=91756066624}"
  : "${MODEL_SHA256:=f3b9ab6394d9de03394b9d95aa75af42ca7025711cf8418857eddd0d213e5f13}"
  : "${MODEL_DISPLAY_NAME:=Hy3 295B-A21B IQ1_M MTP}"
  : "${SERVED_MODEL_NAME:=hy3-iq1-m-mtp}"
  : "${WORK_DIR:=runtime}"
  : "${LLAMA_CPP_DIR:=runtime/llama.cpp}"
  : "${MODEL_DIR:=runtime/models}"
  : "${N_GPU_LAYERS:=auto}"
  : "${SPLIT_MODE:=none}"
  : "${MAIN_GPU:=0}"
  : "${FIT:=1}"
  : "${FIT_TARGET_MIB:=8192}"
  : "${FIT_MIN_CTX:=16384}"
  : "${CTX_SIZE:=65536}"
  : "${KV_CACHE_TYPE_K:=q8_0}"
  : "${KV_CACHE_TYPE_V:=q8_0}"
  : "${KV_CACHE_TYPE_K_DRAFT:=q8_0}"
  : "${KV_CACHE_TYPE_V_DRAFT:=q8_0}"
  : "${PARALLEL:=1}"
  : "${BATCH_SIZE:=1024}"
  : "${UBATCH_SIZE:=256}"
  : "${THREADS:=16}"
  : "${THREADS_BATCH:=20}"
  : "${FLASH_ATTN:=on}"
  : "${USE_MMAP:=0}"
  : "${DIRECT_IO:=0}"
  : "${ENABLE_MTP:=1}"
  : "${SPEC_DRAFT_N_MAX:=3}"
  : "${SPEC_DRAFT_N_MIN:=1}"
  : "${SPEC_DRAFT_P_MIN:=0.75}"
  : "${TEMPERATURE:=0.9}"
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
  : "${MIN_RECLAIMABLE_MEMORY_GIB:=100}"
  : "${MIN_FREE_DISK_GIB:=125}"
  : "${MIN_POST_DOWNLOAD_FREE_GIB:=25}"
  : "${SKIP_PREFLIGHT:=0}"
  : "${ALLOW_UNSUPPORTED_HARDWARE:=0}"
  : "${GPU_NAME_PATTERN:=GB10}"
  : "${DOCKER_IMAGE:=llm-sql-hy3-iq1m-mtp-dgx-spark:cuda13}"
  : "${DOCKER_CONTAINER:=llm-sql-hy3-iq1m-mtp-dgx-spark}"
  : "${DOCKER_MODEL_VOLUME:=llm-sql-hy3-iq1m-mtp-model}"
  : "${RESTART_POLICY:=unless-stopped}"
  : "${HF_TOKEN:=}"
  : "${CUDA_VISIBLE_DEVICES:=0}"

  WORK_DIR="$(abs_path "${WORK_DIR}")"
  LLAMA_CPP_DIR="$(abs_path "${LLAMA_CPP_DIR}")"
  MODEL_DIR="$(abs_path "${MODEL_DIR}")"
  MODEL_PATH="${MODEL_DIR}/${MODEL_FILE}"
  MODEL_PARTIAL_PATH="${MODEL_PATH}.partial"
  MODEL_MARKER_PATH="${MODEL_PATH}.sha256-ok"

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

file_size() {
  local path="$1"
  if stat -c '%s' "${path}" >/dev/null 2>&1; then
    stat -c '%s' "${path}"
  else
    stat -f '%z' "${path}"
  fi
}

model_sha256() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${path}" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${path}" | awk '{print $1}'
  else
    echo "Neither sha256sum nor shasum is available." >&2
    return 1
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

compose() {
  docker compose \
    --env-file "${ROOT_DIR}/config.env" \
    -f "${ROOT_DIR}/docker-compose.yml" \
    "$@"
}
