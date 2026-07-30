#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

if [[ "${INSTALL_SYSTEM_PACKAGES}" == "1" ]]; then
  if ! command -v sudo >/dev/null 2>&1; then
    echo "sudo is required when INSTALL_SYSTEM_PACKAGES=1" >&2
    exit 1
  fi

  sudo apt-get update
  sudo apt-get install -y \
    build-essential \
    cmake \
    curl \
    git \
    git-lfs \
    ninja-build \
    python3 \
    python3-pip \
    python3-venv
fi

require_cmd git
require_cmd cmake
require_cmd python3

if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi
else
  echo "nvidia-smi not found. Continue only if the DGX CUDA environment is already configured."
fi

mkdir -p "${WORK_DIR}" "$(dirname "${HF_MODEL_DIR}")" "$(dirname "${GGUF_MODEL}")"

if [[ ! -x "$(venv_python)" ]]; then
  python3 -m venv "${WORK_DIR}/.venv"
fi

"$(venv_pip)" install --upgrade pip wheel setuptools
"$(venv_pip)" install --upgrade "huggingface_hub[cli]" numpy protobuf sentencepiece safetensors transformers

if command -v git-lfs >/dev/null 2>&1; then
  git lfs install
else
  echo "git-lfs not found. Hugging Face CLI can still download regular files, but LFS is recommended."
fi

echo "DGX preparation complete."
