#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ./scripts/03_download_model.sh; then
  :
else
  download_status="$?"
  if [[ "${download_status}" == "65" ]]; then
    echo "A non-retryable model data error was detected." >&2
    echo "The container will remain idle and unhealthy instead of repeatedly hashing the 85.46 GiB file." >&2
    echo "Inspect /models with ./scripts/docker_shell.sh, move or remove the reported bad file, then restart the container." >&2
    exec sleep infinity
  fi
  exit "${download_status}"
fi
exec ./scripts/04_start_server.sh
