#!/usr/bin/env bash

autorun_refuse_root() {
  if [[ "${EUID}" -eq 0 && "${ALLOW_ROOT_PIPELINE:-0}" != "1" ]]; then
    cat >&2 <<'EOF'
[AutorunEnum] Do not run the whole pipeline with sudo.
sudo discards the active virtualenv and creates root-owned workspace files.
Run it as the normal user. If Docker is the blocker, add that user to the docker group.
Set ALLOW_ROOT_PIPELINE=1 only for an intentional root-only recovery run.
EOF
    return 1
  fi
}

autorun_resolve_python() {
  local repo_root="$1"
  local script_dir="$2"
  local candidate=""

  if [[ -n "${PYTHON_BIN:-}" ]]; then
    if [[ -x "${PYTHON_BIN}" ]]; then
      candidate="${PYTHON_BIN}"
    else
      candidate="$(command -v -- "${PYTHON_BIN}" 2>/dev/null || true)"
    fi
  elif [[ -n "${VIRTUAL_ENV:-}" && -x "${VIRTUAL_ENV}/bin/python3" ]]; then
    candidate="${VIRTUAL_ENV}/bin/python3"
  elif [[ -x "${repo_root}/.venv/bin/python3" ]]; then
    candidate="${repo_root}/.venv/bin/python3"
  elif [[ -x "${script_dir}/.venv/bin/python3" ]]; then
    candidate="${script_dir}/.venv/bin/python3"
  else
    candidate="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
  fi

  if [[ -z "${candidate}" || ! -x "${candidate}" ]]; then
    echo "[AutorunEnum] Python interpreter not found." >&2
    echo "Set PYTHON_BIN=/absolute/path/to/venv/bin/python3 and retry." >&2
    return 1
  fi

  AUTORUN_PYTHON="${candidate}"
  export AUTORUN_PYTHON
  echo "[AutorunEnum] Python: ${AUTORUN_PYTHON}"
}
