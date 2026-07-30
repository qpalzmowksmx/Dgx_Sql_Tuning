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
  GGML_CUDA_ENABLE_UNIFIED_MEMORY SKIP_PREFLIGHT ALLOW_UNSUPPORTED_HARDWARE; do
  require_bool "${name}"
done
require_positive_int GGML_OP_OFFLOAD_MIN_BATCH

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
  fail_or_warn "DGX Spark requires Linux; found $(uname -s)."
fi
case "$(uname -m)" in
  aarch64|arm64) ;;
  *) fail_or_warn "DGX Spark is ARM64; found $(uname -m)." ;;
esac
if [[ ! ";${CUDA_ARCHITECTURES};" =~ (^|\;)121(\;|$) ]]; then
  fail_or_warn "DGX Spark GB10 should target SM121; CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES}."
fi

require_cmd nvidia-smi
gpu_name="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n 1 || true)"
if [[ -z "${gpu_name}" ]]; then
  fail_or_warn "nvidia-smi did not report a GPU."
elif [[ "${gpu_name}" != *"${GPU_NAME_PATTERN}"* ]]; then
  fail_or_warn "Expected GPU name containing '${GPU_NAME_PATTERN}', found '${gpu_name}'."
fi
echo "GPU: ${gpu_name}"

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
  if ! nvcc --version | grep -Eq 'release 13\.'; then
    fail_or_warn "SM121 build expects CUDA 13.x; nvcc reports: $(nvcc --version | tail -n 1)"
  fi
fi

memory_kib="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo 2>/dev/null || printf '0')"
memory_gib="$((memory_kib / 1024 / 1024))"
if (( memory_gib < MIN_SYSTEM_MEMORY_GIB )); then
  fail_or_warn "UD-IQ3_XXS needs the 128 GB DGX Spark memory class; found about ${memory_gib} GiB."
fi
echo "System memory: about ${memory_gib} GiB"

disk_path="${MODEL_CACHE_DIR}"
if [[ "${mode}" == "docker" ]]; then
  docker_root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
  if [[ -n "${docker_root}" && -d "${docker_root}" ]]; then
    disk_path="${docker_root}"
  else
    disk_path="${ROOT_DIR}"
  fi
else
  mkdir -p "${MODEL_CACHE_DIR}"
fi

available_kib="$(df -Pk "${disk_path}" | awk 'NR == 2 {print $4}')"
available_gib="$((available_kib / 1024 / 1024))"
if (( available_gib < MIN_FREE_DISK_GIB )); then
  fail_or_warn "${disk_path} has about ${available_gib} GiB free; ${MIN_FREE_DISK_GIB} GiB is required before first download/build."
fi
echo "Model/build storage free: about ${available_gib} GiB (${disk_path})"
echo "Preflight passed (${mode}, SM${CUDA_ARCHITECTURES})."
