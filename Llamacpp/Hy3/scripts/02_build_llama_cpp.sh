#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

require_cmd git
require_cmd cmake
require_cmd nvcc
require_cmd curl

mkdir -p "${WORK_DIR}" "${MODEL_DIR}"

patch_dir="${WORK_DIR}/hy3-patches"
patch_01="${patch_dir}/${HY3_PATCH_01_FILE}"
patch_02="${patch_dir}/${HY3_PATCH_02_FILE}"
mkdir -p "${patch_dir}"

download_patch() {
  local file="$1"
  local sha="$2"
  local path="${patch_dir}/${file}"
  local partial="${path}.partial"
  local actual_sha

  if [[ -f "${path}" ]] && [[ "$(model_sha256 "${path}")" == "${sha}" ]]; then
    return 0
  fi

  curl --fail --location --retry 5 --retry-all-errors \
    --output "${partial}" "${HY3_PATCH_BASE_URL}/${file}"
  actual_sha="$(model_sha256 "${partial}")"
  if [[ "${actual_sha}" != "${sha}" ]]; then
    echo "Patch SHA-256 mismatch: ${file}" >&2
    echo "Expected: ${sha}" >&2
    echo "Actual:   ${actual_sha}" >&2
    exit 1
  fi
  mv "${partial}" "${path}"
}

download_patch "${HY3_PATCH_01_FILE}" "${HY3_PATCH_01_SHA256}"
download_patch "${HY3_PATCH_02_FILE}" "${HY3_PATCH_02_SHA256}"

if [[ ! -e "${LLAMA_CPP_DIR}" ]]; then
  git clone --filter=blob:none --single-branch --branch "${LLAMA_CPP_BRANCH}" \
    "${LLAMA_CPP_REPO}" "${LLAMA_CPP_DIR}"
elif [[ ! -d "${LLAMA_CPP_DIR}/.git" ]]; then
  echo "LLAMA_CPP_DIR exists but is not a git repository: ${LLAMA_CPP_DIR}" >&2
  exit 1
fi

# Remove only the wrapper-owned patch set before switching commits. Restore it
# if unrelated tracked edits remain, then refuse to overwrite user work.
patch_02_was_applied=0
patch_01_was_applied=0
if git -C "${LLAMA_CPP_DIR}" apply --reverse --check "${patch_02}" >/dev/null 2>&1; then
  git -C "${LLAMA_CPP_DIR}" apply --reverse "${patch_02}"
  patch_02_was_applied=1
fi
if git -C "${LLAMA_CPP_DIR}" apply --reverse --check "${patch_01}" >/dev/null 2>&1; then
  git -C "${LLAMA_CPP_DIR}" apply --reverse "${patch_01}"
  patch_01_was_applied=1
fi

if [[ -n "$(git -C "${LLAMA_CPP_DIR}" status --porcelain --untracked-files=all)" ]]; then
  if [[ "${patch_01_was_applied}" == "1" ]]; then
    git -C "${LLAMA_CPP_DIR}" apply "${patch_01}" || true
  fi
  if [[ "${patch_02_was_applied}" == "1" ]]; then
    git -C "${LLAMA_CPP_DIR}" apply "${patch_02}" || true
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

git -C "${LLAMA_CPP_DIR}" apply --check "${patch_01}"
git -C "${LLAMA_CPP_DIR}" apply "${patch_01}"
git -C "${LLAMA_CPP_DIR}" apply --check "${patch_02}"
git -C "${LLAMA_CPP_DIR}" apply "${patch_02}"

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
  -DLLAMA_OPENSSL=OFF \
  -DLLAMA_BUILD_SERVER=ON \
  -DLLAMA_BUILD_UI=OFF \
  -DLLAMA_USE_PREBUILT_UI=OFF \
  -DLLAMA_BUILD_TESTS=OFF

cmake --build "${LLAMA_CPP_DIR}/build" --config Release -j "$(nproc)" \
  --target llama-server llama-cli llama-bench

for binary in llama-server llama-cli llama-bench; do
  if [[ ! -x "${LLAMA_CPP_DIR}/build/bin/${binary}" ]]; then
    echo "Missing binary after build: ${binary}" >&2
    exit 1
  fi
done

echo "Hy3-capable DGX Spark CUDA build complete."
echo "Base commit: ${actual_ref}"
echo "Patches: ${HY3_PATCH_01_FILE}, ${HY3_PATCH_02_FILE} (SHA-256 pinned)"
"${LLAMA_CPP_DIR}/build/bin/llama-server" --list-devices
