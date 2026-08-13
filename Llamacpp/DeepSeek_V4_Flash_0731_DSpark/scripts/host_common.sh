#!/usr/bin/env bash

ds4_load_config() {
  local model_dir="$1"
  local config_file="${model_dir}/config.env"
  local runtime_file="${model_dir}/runtime.env"
  if [[ ! -f "${config_file}" ]]; then
    cp "${model_dir}/config.env.example" "${config_file}"
    printf '[DS4] created %s from config.env.example\n' "${config_file}"
  fi
  set -a
  # shellcheck disable=SC1090
  source "${config_file}"
  # shellcheck disable=SC1090
  source "${runtime_file}"
  set +a
}

ds4_require_runtime() {
  local model_dir="$1"
  local image="${DOCKER_IMAGE:-llm-sql-dsv4-0731-dspark-dgx-spark:antirez-b7e9f00}"
  local expected_revision="${DS4_COMMIT:-}"
  local expected_wrapper_revision="${DS4_WRAPPER_REVISION:-}"
  local actual_revision=""
  local actual_wrapper_revision=""
  command -v docker >/dev/null 2>&1 || {
    printf '[DS4] docker was not found\n' >&2
    return 1
  }
  docker compose version >/dev/null 2>&1 || {
    printf '[DS4] docker compose was not found\n' >&2
    return 1
  }
  if docker image inspect "${image}" >/dev/null 2>&1; then
    actual_revision="$(docker image inspect "${image}" \
      --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' \
      2>/dev/null || true)"
    actual_wrapper_revision="$(docker image inspect "${image}" \
      --format '{{ index .Config.Labels "io.llm-sql.wrapper.revision" }}' \
      2>/dev/null || true)"
  fi
  if [[ -z "${actual_revision}" \
        || "${actual_revision}" != "${expected_revision}" \
        || -z "${actual_wrapper_revision}" \
        || "${actual_wrapper_revision}" != "${expected_wrapper_revision}" ]]; then
    if [[ -n "${actual_revision}" ]]; then
      printf '[DS4] image revision mismatch: expected=%s actual=%s\n' \
        "${expected_revision}" "${actual_revision}" >&2
    fi
    if [[ "${actual_wrapper_revision}" != "${expected_wrapper_revision}" ]]; then
      printf '[DS4] wrapper revision mismatch: expected=%s actual=%s\n' \
        "${expected_wrapper_revision}" "${actual_wrapper_revision:-missing}" >&2
    fi
    if [[ "${DS4_AUTO_BUILD:-1}" =~ ^(1|true|TRUE|yes|YES|on|ON)$ ]]; then
      printf '[DS4] required current image is missing: %s\n' "${image}"
      printf '[DS4] building it once from the bundled pinned source...\n'
      "${model_dir}/build.sh"
    else
      printf '[DS4] required image is missing: %s\n' "${image}" >&2
      printf '[DS4] run %s/build.sh on the DGX.\n' "${model_dir}" >&2
      return 1
    fi
  fi
  actual_revision="$(docker image inspect "${image}" \
    --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' \
    2>/dev/null || true)"
  actual_wrapper_revision="$(docker image inspect "${image}" \
    --format '{{ index .Config.Labels "io.llm-sql.wrapper.revision" }}' \
    2>/dev/null || true)"
  [[ "${actual_revision}" == "${expected_revision}" ]] || {
    printf '[DS4] image build did not create the expected revision: %s\n' \
      "${expected_revision}" >&2
    return 1
  }
  [[ "${actual_wrapper_revision}" == "${expected_wrapper_revision}" ]] || {
    printf '[DS4] image build did not create the expected wrapper revision: %s\n' \
      "${expected_wrapper_revision}" >&2
    return 1
  }
  [[ -f "${model_dir}/models/${BASE_GGUF_FILE}" ]] || {
    printf '[DS4] base model is missing: %s\n' "${model_dir}/models/${BASE_GGUF_FILE}" >&2
    return 1
  }
  if [[ "${DS4_ENABLE_DSPARK:-1}" =~ ^(1|true|yes|on)$ ]]; then
    [[ -f "${model_dir}/models/${DSPARK_SUPPORT_GGUF_FILE}" ]] || {
      printf '[DS4] DSpark support GGUF is missing: %s\n' "${model_dir}/models/${DSPARK_SUPPORT_GGUF_FILE}" >&2
      return 1
    }
  fi
}

ds4_wait_for_health() {
  local container="$1"
  local timeout_sec="$2"
  local started_at status
  started_at="$(date +%s)"
  while true; do
    status="$(docker inspect "${container}" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' 2>/dev/null || true)"
    case "${status}" in
      healthy) return 0 ;;
      unhealthy|exited|dead)
        printf '[DS4] container failed: %s\n' "${status}" >&2
        docker inspect "${container}" \
          --format '[DS4] state={{.State.Status}} exit={{.State.ExitCode}} error={{.State.Error}}' \
          >&2 2>/dev/null || true
        docker logs --tail 200 "${container}" >&2 2>/dev/null || true
        return 1
        ;;
    esac
    if (( $(date +%s) - started_at >= timeout_sec )); then
      printf '[DS4] health timeout; last state: %s\n' "${status:-missing}" >&2
      return 1
    fi
    sleep 5
  done
}
