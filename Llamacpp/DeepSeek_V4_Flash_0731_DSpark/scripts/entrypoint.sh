#!/usr/bin/env bash
set -Eeuo pipefail

die() {
  printf '[DS4] ERROR: %s\n' "$*" >&2
  exit 1
}

enabled() {
  local normalized
  normalized="$(printf '%s' "${1}" | tr '[:upper:]' '[:lower:]')"
  case "${normalized}" in
    1|true|yes|on) return 0 ;;
    0|false|no|off|"") return 1 ;;
    *) die "expected a boolean value, got: $1" ;;
  esac
}

BASE_PATH="/models/${BASE_GGUF_FILE:?BASE_GGUF_FILE is required}"
DSPARK_SUPPORT_PATH="/models/${DSPARK_SUPPORT_GGUF_FILE:?DSPARK_SUPPORT_GGUF_FILE is required}"

[[ -f "${BASE_PATH}" ]] || die "base GGUF is missing: ${BASE_PATH}"

spec_args=()
if enabled "${DS4_ENABLE_DSPARK:-1}"; then
  [[ -f "${DSPARK_SUPPORT_PATH}" ]] || die "0731 DSpark support GGUF is missing: ${DSPARK_SUPPORT_PATH}"
  # The official 0731 path supplies the support GGUF through --mtp and then
  # selects the DSpark runtime. It replaces legacy MTP; the two do not stack.
  spec_args=(
    --mtp "${DSPARK_SUPPORT_PATH}"
    --dspark
    --dspark-confidence "${DSPARK_CONFIDENCE:-0.7}"
  )
fi

server_args=(
  --cuda
  --model "${BASE_PATH}"
  "${spec_args[@]}"
  --ctx "${CTX_SIZE:-32768}"
  --tokens "${DEFAULT_MAX_TOKENS:-16384}"
  --threads "${THREADS:-16}"
  --host "${HOST:-0.0.0.0}"
  --port "${PORT:-8080}"
  --kv-disk-dir /var/lib/ds4/kv
  --kv-disk-space-mb "${KV_DISK_SPACE_MB:-8192}"
  --kv-cache-min-tokens "${KV_CACHE_MIN_TOKENS:-512}"
  --kv-cache-cold-max-tokens "${KV_CACHE_COLD_MAX_TOKENS:-30000}"
  --kv-cache-continued-interval-tokens "${KV_CACHE_CONTINUED_INTERVAL_TOKENS:-10000}"
)

[[ -n "${GPU_VRAM:-}" ]] && server_args+=(--gpu-vram "${GPU_VRAM}")
[[ -n "${PREFILL_CHUNK:-}" ]] && server_args+=(--prefill-chunk "${PREFILL_CHUNK}")
if enabled "${SSD_STREAMING:-0}"; then
  server_args+=(--ssd-streaming)
  [[ -n "${SSD_STREAMING_CACHE_EXPERTS:-}" ]] && \
    server_args+=(--ssd-streaming-cache-experts "${SSD_STREAMING_CACHE_EXPERTS}")
fi

enabled "${ENABLE_CORS:-1}" && server_args+=(--cors)
enabled "${WARM_WEIGHTS:-0}" && server_args+=(--warm-weights)
enabled "${QUALITY_MODE:-0}" && server_args+=(--quality)

printf '[DS4] starting %s with DSpark=%s confidence=%s ctx=%s SSD-streaming=%s on %s:%s\n' \
  "${SERVED_MODEL_NAME:-deepseek-v4-flash-0731-dspark}" \
  "${DS4_ENABLE_DSPARK:-1}" \
  "${DSPARK_CONFIDENCE:-0.7}" \
  "${CTX_SIZE:-32768}" \
  "${SSD_STREAMING:-0}" \
  "${HOST:-0.0.0.0}" \
  "${PORT:-8080}"

exec /opt/ds4/ds4-server "${server_args[@]}"
