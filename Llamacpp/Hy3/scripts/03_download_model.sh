#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

require_cmd curl
mkdir -p "${MODEL_DIR}"

expected_marker="${MODEL_SHA256}  ${MODEL_FILE}"
readonly EX_DATAERR=65

if [[ -f "${MODEL_PATH}" ]]; then
  actual_size="$(file_size "${MODEL_PATH}")"
  if [[ "${actual_size}" != "${MODEL_SIZE_BYTES}" ]]; then
    echo "Existing model has the wrong size: ${MODEL_PATH}" >&2
    echo "Expected ${MODEL_SIZE_BYTES} bytes, found ${actual_size}." >&2
    echo "Move the bad file aside, then rerun this downloader." >&2
    exit "${EX_DATAERR}"
  fi

  if [[ -f "${MODEL_MARKER_PATH}" ]] && \
     [[ "$(<"${MODEL_MARKER_PATH}")" == "${expected_marker}" ]]; then
    echo "Model already downloaded and verified: ${MODEL_PATH}"
    exit 0
  fi

  echo "Model size matches; computing SHA-256 once (about 85.46 GiB to read)."
  actual_sha="$(model_sha256 "${MODEL_PATH}")"
  if [[ "${actual_sha}" != "${MODEL_SHA256}" ]]; then
    echo "SHA-256 mismatch for ${MODEL_PATH}" >&2
    echo "Expected: ${MODEL_SHA256}" >&2
    echo "Actual:   ${actual_sha}" >&2
    echo "Move the bad file aside, then rerun this downloader." >&2
    exit "${EX_DATAERR}"
  fi
  printf '%s\n' "${expected_marker}" > "${MODEL_MARKER_PATH}"
  echo "Model verified: ${MODEL_PATH}"
  exit 0
fi

need_download=1
if [[ -f "${MODEL_PARTIAL_PATH}" ]]; then
  partial_size="$(file_size "${MODEL_PARTIAL_PATH}")"
  if (( partial_size > MODEL_SIZE_BYTES )); then
    echo "Partial file is larger than expected: ${MODEL_PARTIAL_PATH}" >&2
    echo "Move it aside, then rerun this downloader." >&2
    exit "${EX_DATAERR}"
  fi
  if [[ "${partial_size}" == "${MODEL_SIZE_BYTES}" ]]; then
    need_download=0
    echo "Partial file is complete; continuing with SHA-256 verification."
  else
    echo "Resuming at byte ${partial_size} of ${MODEL_SIZE_BYTES}."
  fi
else
  echo "Downloading ${MODEL_REPO}/${MODEL_FILE} (${MODEL_SIZE_BYTES} bytes, about 85.46 GiB)."
fi

if [[ "${need_download}" == "1" ]]; then
  download_url="https://huggingface.co/${MODEL_REPO}/resolve/${MODEL_REVISION}/${MODEL_FILE}?download=true"
  curl_args=(
    --fail
    --location
    --retry 8
    --retry-delay 5
    --retry-all-errors
    --continue-at -
    --output "${MODEL_PARTIAL_PATH}"
  )
  if [[ -n "${HF_TOKEN}" ]]; then
    curl_args+=(--header "Authorization: Bearer ${HF_TOKEN}")
  fi

  curl "${curl_args[@]}" "${download_url}"
fi

actual_size="$(file_size "${MODEL_PARTIAL_PATH}")"
if [[ "${actual_size}" != "${MODEL_SIZE_BYTES}" ]]; then
  echo "Download did not reach the expected size." >&2
  echo "Expected ${MODEL_SIZE_BYTES} bytes, found ${actual_size}. Rerun to resume." >&2
  exit 1
fi

echo "Download complete; verifying SHA-256 (about 85.46 GiB to read)."
actual_sha="$(model_sha256 "${MODEL_PARTIAL_PATH}")"
if [[ "${actual_sha}" != "${MODEL_SHA256}" ]]; then
  echo "SHA-256 mismatch; keeping the partial file for inspection." >&2
  echo "Expected: ${MODEL_SHA256}" >&2
  echo "Actual:   ${actual_sha}" >&2
  exit "${EX_DATAERR}"
fi

mv "${MODEL_PARTIAL_PATH}" "${MODEL_PATH}"
printf '%s\n' "${expected_marker}" > "${MODEL_MARKER_PATH}"
echo "Model downloaded and verified: ${MODEL_PATH}"
