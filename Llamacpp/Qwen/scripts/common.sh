#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONFIG_KEYS=(
  MODEL_FAMILY MODEL_DISPLAY_NAME SERVED_MODEL_NAME MODEL_REPO MODEL_REVISION HF_GGUF_MODEL_REF
  WORK_DIR LLAMA_CPP_DIR HF_MODEL_DIR GGUF_MODEL LLAMA_CPP_REPO LLAMA_CPP_REF GGUF_OUTTYPE
  KV_CACHE_TYPE KV_CACHE_TYPE_K KV_CACHE_TYPE_V HOST BIND_ADDRESS PORT CTX_SIZE N_GPU_LAYERS PARALLEL
  BATCH_SIZE UBATCH_SIZE THREADS FLASH_ATTN LLAMA_SERVER_EXTRA_ARGS TEMPERATURE TOP_P TOP_K MIN_P
  PRESENCE_PENALTY FREQUENCY_PENALTY REPETITION_PENALTY SEED INSTALL_SYSTEM_PACKAGES
  START_SERVER CONTAINER_WORKDIR DOCKER_IMAGE DOCKER_CONTAINER DOCKER_HF_CACHE_VOLUME
  DOCKER_CUDA_IMAGE HF_TOKEN
)

ensure_config() {
  if [[ ! -f "${ROOT_DIR}/config.env" ]]; then
    cp "${ROOT_DIR}/config.env.example" "${ROOT_DIR}/config.env"
    echo "Created ${ROOT_DIR}/config.env"
  fi
}

load_config() {
  local key
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

  local index
  for ((index = 0; index < ${#override_names[@]}; index++)); do
    key="${override_names[${index}]}"
    printf -v "${key}" '%s' "${override_values[${index}]}"
    export "${key}"
  done

  : "${MODEL_FAMILY:=qwen}"
  : "${MODEL_DISPLAY_NAME:=Qwen llama.cpp server}"
  : "${SERVED_MODEL_NAME:=qwen-sql-tuner}"
  : "${MODEL_REPO:=}"
  : "${MODEL_REVISION:=main}"
  : "${HF_GGUF_MODEL_REF:=}"
  if [[ -z "${MODEL_REPO}" && -z "${HF_GGUF_MODEL_REF}" ]]; then
    MODEL_REPO="Qwen/Qwen3.6-27B"
  fi
  : "${WORK_DIR:=runtime}"
  : "${LLAMA_CPP_DIR:=runtime/llama.cpp}"
  : "${HF_MODEL_DIR:=runtime/models/${MODEL_FAMILY}-hf}"
  : "${GGUF_MODEL:=runtime/models/${MODEL_FAMILY}-${GGUF_OUTTYPE:-bf16}.gguf}"
  : "${LLAMA_CPP_REPO:=https://github.com/ggml-org/llama.cpp.git}"
  : "${LLAMA_CPP_REF:=master}"
  : "${GGUF_OUTTYPE:=bf16}"
  : "${KV_CACHE_TYPE:=f16}"
  : "${KV_CACHE_TYPE_K:=${KV_CACHE_TYPE}}"
  : "${KV_CACHE_TYPE_V:=${KV_CACHE_TYPE}}"
  : "${HOST:=127.0.0.1}"
  : "${BIND_ADDRESS:=127.0.0.1}"
  : "${PORT:=8080}"
  : "${CTX_SIZE:=131072}"
  : "${N_GPU_LAYERS:=999}"
  : "${PARALLEL:=1}"
  : "${BATCH_SIZE:=2048}"
  : "${UBATCH_SIZE:=512}"
  : "${THREADS:=16}"
  : "${FLASH_ATTN:=1}"
  : "${LLAMA_SERVER_EXTRA_ARGS:=}"
  : "${TEMPERATURE:=0.6}"
  : "${TOP_P:=0.95}"
  : "${TOP_K:=20}"
  : "${MIN_P:=0.0}"
  : "${PRESENCE_PENALTY:=0.0}"
  : "${FREQUENCY_PENALTY:=0.0}"
  : "${REPETITION_PENALTY:=1.0}"
  : "${SEED:=42}"
  : "${INSTALL_SYSTEM_PACKAGES:=0}"
  : "${START_SERVER:=1}"
  : "${CONTAINER_WORKDIR:=/workspace/llamacpp}"
  : "${DOCKER_IMAGE:=llamacpp-${MODEL_FAMILY}-server:cuda}"
  : "${DOCKER_CONTAINER:=llamacpp-${MODEL_FAMILY}-server}"
  : "${DOCKER_HF_CACHE_VOLUME:=llamacpp-${MODEL_FAMILY}-huggingface-cache}"
  : "${DOCKER_CUDA_IMAGE:=nvidia/cuda:12.8.1-devel-ubuntu24.04}"

  WORK_DIR="$(abs_path "${WORK_DIR}")"
  LLAMA_CPP_DIR="$(abs_path "${LLAMA_CPP_DIR}")"
  HF_MODEL_DIR="$(abs_path "${HF_MODEL_DIR}")"
  GGUF_MODEL="$(abs_path "${GGUF_MODEL}")"

  export MODEL_FAMILY MODEL_DISPLAY_NAME SERVED_MODEL_NAME
  export MODEL_REPO MODEL_REVISION HF_GGUF_MODEL_REF WORK_DIR LLAMA_CPP_DIR HF_MODEL_DIR GGUF_MODEL
  export LLAMA_CPP_REPO LLAMA_CPP_REF GGUF_OUTTYPE KV_CACHE_TYPE KV_CACHE_TYPE_K KV_CACHE_TYPE_V
  export HOST BIND_ADDRESS PORT CTX_SIZE N_GPU_LAYERS PARALLEL BATCH_SIZE UBATCH_SIZE THREADS FLASH_ATTN
  export LLAMA_SERVER_EXTRA_ARGS TEMPERATURE TOP_P TOP_K MIN_P PRESENCE_PENALTY
  export FREQUENCY_PENALTY REPETITION_PENALTY SEED INSTALL_SYSTEM_PACKAGES START_SERVER
  export CONTAINER_WORKDIR DOCKER_IMAGE DOCKER_CONTAINER DOCKER_HF_CACHE_VOLUME DOCKER_CUDA_IMAGE
  export HF_TOKEN="${HF_TOKEN:-}"
}

abs_path() {
  local path="$1"
  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s/%s\n' "${ROOT_DIR}" "${path}"
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing command: ${cmd}" >&2
    exit 1
  fi
}

venv_python() {
  printf '%s/.venv/bin/python\n' "${WORK_DIR}"
}

venv_pip() {
  printf '%s/.venv/bin/pip\n' "${WORK_DIR}"
}

venv_hf() {
  printf '%s/.venv/bin/huggingface-cli\n' "${WORK_DIR}"
}
