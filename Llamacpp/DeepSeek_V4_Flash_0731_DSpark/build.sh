#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
if [[ ! -f "${CONFIG_FILE}" ]]; then
  cp "${SCRIPT_DIR}/config.env.example" "${CONFIG_FILE}"
  echo "Created ${CONFIG_FILE} from config.env.example"
fi

set -a
# shellcheck disable=SC1090
source "${CONFIG_FILE}"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/runtime.env"
set +a

PIN_FILE="${SCRIPT_DIR}/vendor/ds4-src/.pinned-commit"
[[ -f "${PIN_FILE}" ]] || {
  echo "Pinned ds4 source is missing. Run ./prepare_online.sh --source-only first." >&2
  exit 1
}
[[ "$(cat "${PIN_FILE}")" == "${DS4_COMMIT}" ]] || {
  echo "Pinned source commit does not match config.env" >&2
  exit 1
}

docker build \
  --build-arg "CUDA_IMAGE=${CUDA_IMAGE}" \
  --build-arg "DS4_REF=${DS4_REF}" \
  --build-arg "DS4_COMMIT=${DS4_COMMIT}" \
  --build-arg "DS4_WRAPPER_REVISION=${DS4_WRAPPER_REVISION}" \
  --build-arg "BUILD_JOBS=${BUILD_JOBS:-8}" \
  --tag "${DOCKER_IMAGE}" \
  "${SCRIPT_DIR}"

docker image inspect "${DOCKER_IMAGE}" \
  --format 'DS4 image={{.RepoTags}} size={{.Size}}'

actual_revision="$(docker image inspect "${DOCKER_IMAGE}" \
  --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}')"
actual_wrapper_revision="$(docker image inspect "${DOCKER_IMAGE}" \
  --format '{{ index .Config.Labels "io.llm-sql.wrapper.revision" }}')"
[[ "${actual_revision}" == "${DS4_COMMIT}" ]] || {
  echo "Built image DS4 revision mismatch: ${actual_revision}" >&2
  exit 1
}
[[ "${actual_wrapper_revision}" == "${DS4_WRAPPER_REVISION}" ]] || {
  echo "Built image wrapper revision mismatch: ${actual_wrapper_revision}" >&2
  exit 1
}
