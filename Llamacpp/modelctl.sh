#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS=(DeepSeekV4FlashDgxSpark Hy3 Qwen)

usage() {
  cat <<'EOF'
Usage:
  ./modelctl.sh start <model>
  ./modelctl.sh stop
  ./modelctl.sh status

Models: DeepSeekV4FlashDgxSpark, Hy3, Qwen

Only one model stack is started at a time. Model caches and Open WebUI data are
named volumes and are not deleted by stop or model switching.
EOF
}

is_model() {
  local candidate="$1"
  local model
  for model in "${MODELS[@]}"; do
    [[ "${candidate}" == "${model}" ]] && return 0
  done
  return 1
}

compose_for() {
  local model="$1"
  shift
  local model_dir="${ROOT_DIR}/${model}"
  local -a args=(docker compose -f "${model_dir}/docker-compose.yml")
  if [[ -f "${model_dir}/config.env" ]]; then
    args+=(--env-file "${model_dir}/config.env")
  fi
  "${args[@]}" "$@"
}

stop_all() {
  "${ROOT_DIR}/offline_proxy.sh" stop || true
  local model
  for model in "${MODELS[@]}"; do
    compose_for "${model}" down --remove-orphans >/dev/null 2>&1 || true
  done
  local reasoning_dir="${ROOT_DIR}/Hy3"
  if [[ -f "${reasoning_dir}/Reasoning-docker-compose.yml" ]]; then
    local -a reasoning_args=(docker compose -f "${reasoning_dir}/Reasoning-docker-compose.yml")
    [[ -f "${reasoning_dir}/config.env" ]] && reasoning_args+=(--env-file "${reasoning_dir}/config.env")
    [[ -f "${reasoning_dir}/Reasoning-config.env" ]] && reasoning_args+=(--env-file "${reasoning_dir}/Reasoning-config.env")
    "${reasoning_args[@]}" down --remove-orphans >/dev/null 2>&1 || true
  fi
  echo "Stopped Llamacpp model containers. Persistent volumes were preserved."
}

start_model() {
  local model="$1"
  local model_dir="${ROOT_DIR}/${model}"

  if [[ -f "${model_dir}/config.env.example" && ! -f "${model_dir}/config.env" ]]; then
    cp "${model_dir}/config.env.example" "${model_dir}/config.env"
    echo "Created ${model_dir}/config.env from the example."
  fi

  stop_all
  compose_for "${model}" up -d --build
  echo "Started ${model}."
  echo "API:    http://127.0.0.1:8080/v1/models"
  echo "Web UI: http://127.0.0.1:3000"
}

case "${1:-}" in
  start)
    if [[ $# -ne 2 ]] || ! is_model "$2"; then
      usage >&2
      exit 2
    fi
    start_model "$2"
    ;;
  stop)
    [[ $# -eq 1 ]] || { usage >&2; exit 2; }
    stop_all
    ;;
  status)
    [[ $# -eq 1 ]] || { usage >&2; exit 2; }
    docker ps --filter label=com.docker.compose.service \
      --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
