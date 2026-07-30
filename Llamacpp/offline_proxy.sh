#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${TMPDIR:-/tmp}/llm-sql-offline-proxy-${UID}.pid"
LOG_FILE="${TMPDIR:-/tmp}/llm-sql-offline-proxy-${UID}.log"

stop_proxy() {
  if [[ -f "${PID_FILE}" ]]; then
    pid="$(cat "${PID_FILE}")"
    if [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" >/dev/null 2>&1; then
      kill "${pid}"
      for _ in {1..20}; do
        kill -0 "${pid}" >/dev/null 2>&1 || break
        sleep 0.1
      done
    fi
    rm -f "${PID_FILE}"
  fi
}

case "${1:-}" in
  start)
    [[ $# -eq 4 ]] || {
      echo "Usage: $0 start <container> <container-port> <listen-port>" >&2
      exit 2
    }
    container="$2"
    target_port="$3"
    listen_port="$4"
    stop_proxy
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
    stop_proxy
    exit 1
    ;;
  stop)
    [[ $# -eq 1 ]] || {
      echo "Usage: $0 stop" >&2
      exit 2
    }
    stop_proxy
    ;;
  *)
    echo "Usage: $0 {start <container> <container-port> <listen-port>|stop}" >&2
    exit 2
    ;;
esac
