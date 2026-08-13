#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROXY_BASE="${TMPDIR:-/tmp}/llm-sql-offline-proxy-${UID}"

set_proxy_paths() {
  local name="${1:-default}"
  [[ "${name}" =~ ^[A-Za-z0-9_.-]+$ ]] || {
    echo "Invalid proxy name: ${name}" >&2
    exit 2
  }
  if [[ "${name}" == "default" ]]; then
    PID_FILE="${PROXY_BASE}.pid"
    LOG_FILE="${PROXY_BASE}.log"
  else
    PID_FILE="${PROXY_BASE}-${name}.pid"
    LOG_FILE="${PROXY_BASE}-${name}.log"
  fi
}

stop_proxy_file() {
  local pid_file="$1" pid
  if [[ -f "${pid_file}" ]]; then
    pid="$(cat "${pid_file}")"
    if [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}"
      for _ in {1..20}; do
        kill -0 "${pid}" >/dev/null 2>&1 || break
        sleep 0.1
      done
    fi
    rm -f "${pid_file}"
  fi
}

stop_all_proxies() {
  local pid_file
  for pid_file in "${PROXY_BASE}.pid" "${PROXY_BASE}-"*.pid; do
    [[ -e "${pid_file}" ]] || continue
    stop_proxy_file "${pid_file}"
  done
}

case "${1:-}" in
  start)
    [[ $# -eq 4 || $# -eq 5 ]] || {
      echo "Usage: $0 start <container> <container-port> <listen-port> [name]" >&2
      exit 2
    }
    container="$2"
    target_port="$3"
    listen_port="$4"
    set_proxy_paths "${5:-default}"
    stop_proxy_file "${PID_FILE}"
    target_ip="$(
      docker inspect "${container}" \
        --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
    )"
    [[ -n "${target_ip}" ]] || {
      echo "Cannot determine isolated container IP: ${container}" >&2
      exit 1
    }
    nohup python3 "${SCRIPT_DIR}/offline_proxy.py" \
      --listen-host 127.0.0.1 \
      --listen-port "${listen_port}" \
      --target-host "${target_ip}" \
      --target-port "${target_port}" \
      >"${LOG_FILE}" 2>&1 &
    proxy_pid=$!
    printf '%s\n' "${proxy_pid}" >"${PID_FILE}"
    for _ in {1..50}; do
      if python3 - "${listen_port}" <<'PY' >/dev/null 2>&1
import socket
import sys
with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=0.2):
    pass
PY
      then
        echo "Offline proxy: 127.0.0.1:${listen_port} -> ${container}:${target_port}"
        exit 0
      fi
      kill -0 "${proxy_pid}" >/dev/null 2>&1 || break
      sleep 0.1
    done
    echo "Offline proxy failed to start; see ${LOG_FILE}" >&2
    stop_proxy_file "${PID_FILE}"
    exit 1
    ;;
  stop)
    [[ $# -eq 1 || $# -eq 2 ]] || {
      echo "Usage: $0 stop [name]" >&2
      exit 2
    }
    if [[ $# -eq 1 ]]; then
      stop_all_proxies
    else
      set_proxy_paths "$2"
      stop_proxy_file "${PID_FILE}"
    fi
    ;;
  *)
    echo "Usage: $0 {start <container> <container-port> <listen-port> [name]|stop [name]}" >&2
    exit 2
    ;;
esac
