#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

require_cmd git
require_cmd cmake
require_cmd nvcc

mkdir -p "${WORK_DIR}" "${MODEL_CACHE_DIR}"

test_patch="${ROOT_DIR}/patches/0001-test-dsv4-cuda-single-token.patch"
test_patch_ref="7a02824e968f2ce85ad919169962e0020595d141"

if [[ ! -e "${LLAMA_CPP_DIR}" ]]; then
  git clone --filter=blob:none --single-branch --branch "${LLAMA_CPP_BRANCH}" \
    "${LLAMA_CPP_REPO}" "${LLAMA_CPP_DIR}"
elif [[ ! -d "${LLAMA_CPP_DIR}/.git" ]]; then
  echo "LLAMA_CPP_DIR exists but is not a git repository: ${LLAMA_CPP_DIR}" >&2
  exit 1
fi

# Remove the wrapper-owned test patch before switching commits. If any other
# source change remains, restore the patch and refuse to overwrite user work.
patch_was_applied=0
if git -C "${LLAMA_CPP_DIR}" apply --reverse --check "${test_patch}" >/dev/null 2>&1; then
  git -C "${LLAMA_CPP_DIR}" apply --reverse "${test_patch}"
  patch_was_applied=1
fi

if [[ -n "$(git -C "${LLAMA_CPP_DIR}" status --porcelain)" ]]; then
  if [[ "${patch_was_applied}" == "1" ]]; then
    git -C "${LLAMA_CPP_DIR}" apply "${test_patch}"
  fi
  echo "Refusing to switch a modified llama.cpp source tree: ${LLAMA_CPP_DIR}" >&2
  exit 1
fi

git -C "${LLAMA_CPP_DIR}" fetch origin "${LLAMA_CPP_BRANCH}"
git -C "${LLAMA_CPP_DIR}" checkout --detach "${LLAMA_CPP_REF}"

actual_ref="$(git -C "${LLAMA_CPP_DIR}" rev-parse HEAD)"
if [[ "${actual_ref}" != "${LLAMA_CPP_REF}" ]]; then
  echo "Unexpected llama.cpp commit: ${actual_ref}" >&2
  echo "Expected: ${LLAMA_CPP_REF}" >&2
  exit 1
fi

if [[ "${actual_ref}" == "${test_patch_ref}" ]]; then
  git -C "${LLAMA_CPP_DIR}" apply --check "${test_patch}"
  git -C "${LLAMA_CPP_DIR}" apply "${test_patch}"
  echo "Applied DGX Spark single-token CUDA backend tests."
fi

fa_quants=OFF
native_flag=OFF
if [[ "${GGML_CUDA_FA_ALL_QUANTS}" == "1" ]]; then fa_quants=ON; fi
if [[ "${GGML_NATIVE}" == "1" ]]; then native_flag=ON; fi

cmake \
  -S "${LLAMA_CPP_DIR}" \
  -B "${LLAMA_CPP_DIR}/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_CUDA=ON \
  -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCHITECTURES}" \
  -DGGML_CUDA_FA_ALL_QUANTS="${fa_quants}" \
  -DGGML_NATIVE="${native_flag}" \
  -DLLAMA_CURL=ON \
  -DLLAMA_BUILD_TESTS=ON

cmake --build "${LLAMA_CPP_DIR}/build" --config Release -j "$(nproc)"

for binary in llama-server llama-bench test-backend-ops; do
  if [[ ! -x "${LLAMA_CPP_DIR}/build/bin/${binary}" ]]; then
    echo "Missing binary after build: ${binary}" >&2
    exit 1
  fi
done

echo "DGX Spark CUDA build complete."
echo "Commit: ${actual_ref}"
"${LLAMA_CPP_DIR}/build/bin/llama-server" --list-devices
