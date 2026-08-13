#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
[[ -f "${CONFIG_FILE}" ]] || CONFIG_FILE="${SCRIPT_DIR}/config.env.example"

set -a
# shellcheck disable=SC1090
source "${CONFIG_FILE}"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/runtime.env"
set +a

usage() {
  cat <<'EOF'
Usage:
  ./prepare_online.sh --source-only
  ./prepare_online.sh --models-only
  ./prepare_online.sh --all

Run this on an internet-connected machine. Downloads are resumable. The
resulting directory can then be copied as a whole to the closed DGX network.
EOF
}

[[ $# -eq 1 ]] || { usage >&2; exit 2; }
case "$1" in
  --source-only) WANT_SOURCE=1; WANT_MODELS=0 ;;
  --models-only) WANT_SOURCE=0; WANT_MODELS=1 ;;
  --all) WANT_SOURCE=1; WANT_MODELS=1 ;;
  --help|-h) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

prepare_source() {
  local dst="${SCRIPT_DIR}/vendor/ds4-src"
  local archive_url archive_dir archive_file
  command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
  command -v tar >/dev/null 2>&1 || { echo "tar is required" >&2; exit 1; }
  command -v rsync >/dev/null 2>&1 || { echo "rsync is required" >&2; exit 1; }

  archive_dir="$(mktemp -d)"
  archive_file="${archive_dir}/ds4.tar.gz"
  mkdir -p "${archive_dir}/source" "${dst}"
  archive_url="https://github.com/antirez/ds4/archive/${DS4_COMMIT}.tar.gz"

  # A commit-addressed archive avoids carrying stale Git metadata into the
  # closed network and makes the exact source usable by Docker immediately.
  curl --fail --location --retry 8 --retry-delay 5 \
    --output "${archive_file}" "${archive_url}"
  tar -xzf "${archive_file}" --strip-components=1 -C "${archive_dir}/source"
  [[ -f "${archive_dir}/source/Makefile" ]] || {
    echo "Downloaded DS4 archive does not contain a Makefile" >&2
    exit 1
  }
  printf '%s\n' "${DS4_COMMIT}" > "${archive_dir}/source/.pinned-commit"
  rsync -a --delete "${archive_dir}/source/" "${dst}/"
  rm -rf -- "${archive_dir}"
  echo "Prepared pinned ds4 source: ${DS4_REF} (${DS4_COMMIT})"
}

download_hf_file() {
  local repo="$1" file="$2" dst="${SCRIPT_DIR}/models/$2" part
  part="${dst}.part"
  [[ -f "${dst}" ]] && { echo "Already present: ${dst}"; return; }
  local -a headers=()
  [[ -n "${HF_TOKEN:-}" ]] && headers=(-H "Authorization: Bearer ${HF_TOKEN}")
  mkdir -p "${SCRIPT_DIR}/models"
  echo "Downloading ${repo}/${file}"
  curl --fail --location --retry 8 --retry-delay 5 --continue-at - \
    "${headers[@]}" \
    --output "${part}" \
    "https://huggingface.co/${repo}/resolve/main/${file}?download=true"
  mv "${part}" "${dst}"
}

(( WANT_SOURCE )) && prepare_source
if (( WANT_MODELS )); then
  command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
  download_hf_file "${BASE_HF_REPO}" "${BASE_GGUF_FILE}"
  download_hf_file "${DSPARK_SUPPORT_HF_REPO}" "${DSPARK_SUPPORT_GGUF_FILE}"
fi
