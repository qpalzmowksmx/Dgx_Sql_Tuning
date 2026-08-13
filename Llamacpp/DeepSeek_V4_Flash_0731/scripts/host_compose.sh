#!/usr/bin/env bash

iq3xxs_wait_for_health() {
  local container="$1" timeout="$2" started status
  started="$(date +%s)"
  while true; do
    status="$(docker inspect "${container}" --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' 2>/dev/null || true)"
    case "${status}" in
      healthy) printf '[DeepSeek IQ3_XXS] healthy: %s\n' "${container}"; return 0 ;;
      unhealthy|exited|dead) docker logs --tail 200 "${container}" 2>&1 || true; return 1 ;;
    esac
    (( $(date +%s) - started < timeout )) || { printf '[DeepSeek IQ3_XXS] health timeout: %s (%s)\n' "${container}" "${status:-missing}" >&2; return 1; }
    sleep 5
  done
}

iq3xxs_start_compose() {
  local script_dir="$1" include_ui="$2" model_dir llamacpp_dir compose_file config_file
  model_dir="$(cd -- "${script_dir}/.." && pwd)"
  llamacpp_dir="$(cd -- "${model_dir}/.." && pwd)"
  compose_file="${script_dir}/docker-compose.yml"
  config_file="${model_dir}/config.env"

  source "${model_dir}/scripts/common.sh"
  source "${model_dir}/scripts/local_model.sh"
  load_config
  prepare_compose_local_model "${model_dir}"

  command -v docker >/dev/null 2>&1 || { printf 'docker was not found\n' >&2; return 1; }
  docker compose version >/dev/null 2>&1 || { printf 'docker compose was not found\n' >&2; return 1; }

  if ! docker image inspect "${DOCKER_IMAGE}" >/dev/null 2>&1 \
     && docker image inspect "${LEGACY_DOCKER_IMAGE}" >/dev/null 2>&1; then
    printf '[DeepSeek IQ3_XXS] reusing compatible llama.cpp image: %s\n' "${LEGACY_DOCKER_IMAGE}"
    docker tag "${LEGACY_DOCKER_IMAGE}" "${DOCKER_IMAGE}"
  fi

  if [[ -x "${llamacpp_dir}/modelctl.sh" ]]; then "${llamacpp_dir}/modelctl.sh" stop; fi

  local -a compose=(docker compose --project-directory "${script_dir}" --env-file "${config_file}" -f "${compose_file}")
  "${compose[@]}" config --quiet
  if ! docker image inspect "${DOCKER_IMAGE}" >/dev/null 2>&1; then
    if [[ "${BUILD_ON_START:-0}" = 1 ]]; then
      "${compose[@]}" build deepseek-iq3-xxs
    else
      printf '[DeepSeek IQ3_XXS] missing image: %s\n' "${DOCKER_IMAGE}" >&2
      printf '[DeepSeek IQ3_XXS] run ./build.sh while the build dependencies are reachable.\n' >&2
      return 1
    fi
  fi
  if [[ "${include_ui}" = 1 ]] && ! docker image inspect "${OPEN_WEBUI_IMAGE}" >/dev/null 2>&1; then
    printf '[DeepSeek IQ3_XXS] missing Open WebUI image: %s\n' "${OPEN_WEBUI_IMAGE}" >&2
    return 1
  fi

  "${compose[@]}" up -d --no-build --pull never --remove-orphans
  iq3xxs_wait_for_health "${DOCKER_CONTAINER}" "${MODEL_HEALTH_TIMEOUT_SEC:-7200}"
  if [[ "${include_ui}" = 1 ]]; then
    iq3xxs_wait_for_health "${OPEN_WEBUI_CONTAINER}" "${OPEN_WEBUI_HEALTH_TIMEOUT_SEC:-900}"
    printf '[DeepSeek IQ3_XXS] UI:  http://%s:%s\n' "${OPEN_WEBUI_BIND_ADDRESS:-127.0.0.1}" "${OPEN_WEBUI_PORT:-3000}"
  fi
  printf '[DeepSeek IQ3_XXS] API: http://%s:%s/v1/models\n' "${BIND_ADDRESS:-127.0.0.1}" "${PORT:-8080}"
}
