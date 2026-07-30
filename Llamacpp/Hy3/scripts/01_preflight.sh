#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

mode="${1:-native}"
if [[ "${mode}" != "native" && "${mode}" != "docker" ]]; then
  echo "Usage: $0 [native|docker]" >&2
  exit 2
fi

for name in GGML_CUDA_FA_ALL_QUANTS GGML_NATIVE FIT USE_MMAP DIRECT_IO \
  ENABLE_MTP GGML_CUDA_ENABLE_UNIFIED_MEMORY SKIP_PREFLIGHT \
  ALLOW_UNSUPPORTED_HARDWARE; do
  require_bool "${name}"
done
for name in MODEL_SIZE_BYTES SPEC_DRAFT_N_MAX SPEC_DRAFT_N_MIN \
  GGML_OP_OFFLOAD_MIN_BATCH MIN_SYSTEM_MEMORY_GIB \
  MIN_RECLAIMABLE_MEMORY_GIB MIN_FREE_DISK_GIB \
  MIN_POST_DOWNLOAD_FREE_GIB; do
  require_positive_int "${name}"
done

if [[ "${SKIP_PREFLIGHT}" == "1" ]]; then
  echo "Preflight skipped by SKIP_PREFLIGHT=1."
  exit 0
fi

fail_or_warn() {
  local message="$1"
  if [[ "${ALLOW_UNSUPPORTED_HARDWARE}" == "1" ]]; then
    echo "WARNING: ${message}" >&2
  else
    echo "ERROR: ${message}" >&2
    echo "Set ALLOW_UNSUPPORTED_HARDWARE=1 only after checking the risk." >&2
    exit 1
  fi
}

if [[ "$(uname -s)" != "Linux" ]]; then
  fail_or_warn "This profile targets DGX Spark Linux; found $(uname -s)."
fi
case "$(uname -m)" in
  aarch64|arm64) ;;
  *) fail_or_warn "DGX Spark is ARM64; found $(uname -m)." ;;
esac
if [[ ! ";${CUDA_ARCHITECTURES};" =~ (^|\;)121(-real)?(\;|$) ]]; then
  fail_or_warn "DGX Spark GB10 should target SM121-real; CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES}."
fi

if ! command -v nvidia-smi >/dev/null 2>&1; then
  fail_or_warn "nvidia-smi is not installed."
else
  gpu_name="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n 1 || true)"
  if [[ -z "${gpu_name}" ]]; then
    fail_or_warn "nvidia-smi did not report a GPU."
  elif [[ "${gpu_name}" != *"${GPU_NAME_PATTERN}"* ]]; then
    fail_or_warn "Expected GPU name containing '${GPU_NAME_PATTERN}', found '${gpu_name}'."
  fi
  echo "GPU: ${gpu_name:-unknown}"
fi

if [[ "${mode}" == "docker" ]]; then
  require_cmd docker
  if ! docker compose version >/dev/null 2>&1; then
    echo "Docker Compose v2 is required." >&2
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon is unavailable to the current user." >&2
    exit 1
  fi
  if ! docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -qi nvidia; then
    fail_or_warn "NVIDIA Container Toolkit runtime was not found in docker info."
  fi
else
  require_cmd git
  require_cmd cmake
  require_cmd nvcc
  require_cmd curl
  if ! nvcc --version | grep -Eq 'release 13\.'; then
    fail_or_warn "SM121 build expects CUDA 13.x; nvcc reports: $(nvcc --version | tail -n 1)"
  fi
fi

memory_kib="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || printf '0')"
memory_gib="$((memory_kib / 1024 / 1024))"
if (( memory_gib < MIN_SYSTEM_MEMORY_GIB )); then
  fail_or_warn "Hy3 IQ1_M MTP needs the 128 GB memory class; found about ${memory_gib} GiB."
fi
echo "System memory: about ${memory_gib} GiB"

available_memory_kib="$(awk '/^MemAvailable:/ {print $2; exit}' /proc/meminfo 2>/dev/null || printf '0')"
swap_free_kib="$(awk '/^SwapFree:/ {print $2; exit}' /proc/meminfo 2>/dev/null || printf '0')"
available_memory_gib="$((available_memory_kib / 1024 / 1024))"
swap_free_gib="$((swap_free_kib / 1024 / 1024))"
reclaimable_memory_gib="$(((available_memory_kib + swap_free_kib) / 1024 / 1024))"
if (( reclaimable_memory_gib < MIN_RECLAIMABLE_MEMORY_GIB )); then
  fail_or_warn "Only about ${reclaimable_memory_gib} GiB is currently reclaimable (MemAvailable ${available_memory_gib} GiB + SwapFree ${swap_free_gib} GiB); ${MIN_RECLAIMABLE_MEMORY_GIB} GiB is required. Stop other memory-heavy workloads first."
fi
echo "Currently reclaimable: about ${reclaimable_memory_gib} GiB (MemAvailable ${available_memory_gib} GiB + SwapFree ${swap_free_gib} GiB)"

disk_path="${MODEL_DIR}"
if [[ "${mode}" == "docker" ]]; then
  docker_root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
  if [[ -n "${docker_root}" && -d "${docker_root}" ]]; then
    disk_path="${docker_root}"
  else
    disk_path="${ROOT_DIR}"
  fi
else
  mkdir -p "${MODEL_DIR}"
fi

available_kib="$(df -Pk "${disk_path}" | awk 'NR == 2 {print $4}')"
available_gib="$((available_kib / 1024 / 1024))"
cached_model_bytes=0
cached_partial_bytes=0

if [[ "${mode}" == "native" ]]; then
  if [[ -f "${MODEL_PATH}" ]]; then
    cached_model_bytes="$(file_size "${MODEL_PATH}")"
  elif [[ -f "${MODEL_PARTIAL_PATH}" ]]; then
    cached_partial_bytes="$(file_size "${MODEL_PARTIAL_PATH}")"
  fi
elif docker image inspect "${DOCKER_IMAGE}" >/dev/null 2>&1 && \
     docker volume inspect "${DOCKER_MODEL_VOLUME}" >/dev/null 2>&1; then
  cache_state="$(docker run --rm \
    --entrypoint /bin/sh \
    --env MODEL_FILE="${MODEL_FILE}" \
    --volume "${DOCKER_MODEL_VOLUME}:/models:ro" \
    "${DOCKER_IMAGE}" \
    -c 'if [ -f "/models/${MODEL_FILE}" ]; then stat -c "model:%s" "/models/${MODEL_FILE}"; elif [ -f "/models/${MODEL_FILE}.partial" ]; then stat -c "partial:%s" "/models/${MODEL_FILE}.partial"; else echo none; fi' \
    2>/dev/null || true)"
  case "${cache_state}" in
    model:*) cached_model_bytes="${cache_state#model:}" ;;
    partial:*) cached_partial_bytes="${cache_state#partial:}" ;;
  esac
fi

required_disk_gib="${MIN_FREE_DISK_GIB}"
disk_reason="before the first download/build"
if [[ "${cached_model_bytes}" == "${MODEL_SIZE_BYTES}" ]]; then
  required_disk_gib="${MIN_POST_DOWNLOAD_FREE_GIB}"
  disk_reason="with the complete model already cached"
elif [[ "${cached_partial_bytes}" =~ ^[0-9]+$ ]] && \
     (( cached_partial_bytes > 0 && cached_partial_bytes < MODEL_SIZE_BYTES )); then
  gib_bytes=$((1024 * 1024 * 1024))
  remaining_bytes="$((MODEL_SIZE_BYTES - cached_partial_bytes))"
  remaining_gib="$(((remaining_bytes + gib_bytes - 1) / gib_bytes))"
  required_disk_gib="$((remaining_gib + MIN_POST_DOWNLOAD_FREE_GIB))"
  disk_reason="to finish the partial download and retain ${MIN_POST_DOWNLOAD_FREE_GIB} GiB"
fi

if (( available_gib < required_disk_gib )); then
  fail_or_warn "${disk_path} has about ${available_gib} GiB free; ${required_disk_gib} GiB is required ${disk_reason}."
fi
echo "Model/build storage free: about ${available_gib} GiB (${disk_path}); requiring ${required_disk_gib} GiB ${disk_reason}"
echo "Preflight passed (${mode}, SM${CUDA_ARCHITECTURES})."
