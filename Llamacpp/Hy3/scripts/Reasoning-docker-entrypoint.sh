#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ./scripts/03_download_model.sh; then
  :
else
  download_status="$?"
  if [[ "${download_status}" == "65" ]]; then
    echo "A non-retryable model data error was detected." >&2
    echo "The container will remain idle and unhealthy; inspect /models before restarting." >&2
    exec sleep infinity
  fi
  exit "${download_status}"
fi

exec ./scripts/Reasoning-04_start_server.sh
