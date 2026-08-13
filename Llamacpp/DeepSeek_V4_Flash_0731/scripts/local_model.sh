#!/usr/bin/env bash

local_model_die() { printf '[DeepSeek IQ3_XXS] ERROR: %s\n' "$*" >&2; return 1; }

resolve_host_local_gguf_dir() {
  local root="$1" configured="${LOCAL_GGUF_DIR:-}" relative="${LOCAL_GGUF_RELATIVE_DIR:-runtime/local-gguf}"
  if [[ -z "${configured}" ]]; then configured="${root}/${relative#./}";
  elif [[ "${configured}" != /* ]]; then configured="${root}/${configured#./}"; fi
  printf '%s\n' "${configured}"
}

find_local_gguf_entry() {
  local dir="$1" marker="${EXPECTED_MODEL_MARKER:-UD-IQ3_XXS}" item
  local -a matches=()
  [[ -d "${dir}" ]] || return 3
  while IFS= read -r item; do [[ -n "${item}" ]] && matches+=("${item}"); done < <(
    find "${dir}" -maxdepth 1 -type f -name "*${marker}*-00001-of-*.gguf" -print | LC_ALL=C sort
  )
  if (( ${#matches[@]} == 0 )); then
    while IFS= read -r item; do [[ -n "${item}" ]] && matches+=("${item}"); done < <(
      find "${dir}" -maxdepth 1 -type f -name "*${marker}*.gguf" ! -name '*-?????-of-*.gguf' -print | LC_ALL=C sort
    )
  fi
  (( ${#matches[@]} > 0 )) || return 3
  (( ${#matches[@]} == 1 )) || { local_model_die "multiple ${marker} GGUF entries found in ${dir}"; return 2; }
  printf '%s\n' "${matches[0]}"
}

validate_model_marker() {
  [[ "$(basename -- "$1")" == *"${EXPECTED_MODEL_MARKER:-UD-IQ3_XXS}"* ]] \
    || local_model_die "expected ${EXPECTED_MODEL_MARKER:-UD-IQ3_XXS}, got: $(basename -- "$1")"
}

validate_single_quant_directory() {
  local dir="$1" selected="$2" item
  local -a entries=()
  while IFS= read -r item; do [[ -n "${item}" ]] && entries+=("${item}"); done < <(
    find "${dir}" -maxdepth 1 -type f \( -name '*-00001-of-*.gguf' -o \( -name '*.gguf' ! -name '*-?????-of-*.gguf' \) \) -print | LC_ALL=C sort
  )
  (( ${#entries[@]} == 1 )) || {
    local_model_die "keep exactly one quantized model set in ${dir}; found ${#entries[@]} GGUF entries"
    return 1
  }
  [[ "${entries[0]}" = "${selected}" ]] || {
    local_model_die "selected GGUF does not match the only model entry in ${dir}"
    return 1
  }
}

prepare_compose_local_model() {
  local root="$1" dir selected relative configured="${GGUF_MODEL:-}"
  dir="$(resolve_host_local_gguf_dir "${root}")"
  mkdir -p "${dir}"
  if [[ -n "${configured}" ]]; then
    case "${configured}" in
      /models/*) relative="${configured#/models/}"; selected="${dir}/${relative}" ;;
      "${dir}"/*) selected="${configured}"; relative="${configured#"${dir}"/}" ;;
      /*) local_model_die "GGUF_MODEL must be inside LOCAL_GGUF_DIR: ${configured}"; return 1 ;;
      *) relative="${configured#./}"; selected="${dir}/${relative}" ;;
    esac
    [[ -r "${selected}" ]] || { local_model_die "GGUF is not readable: ${selected}"; return 1; }
  elif selected="$(find_local_gguf_entry "${dir}")"; then
    relative="${selected#"${dir}"/}"
  else
    local_model_die "copy every ${EXPECTED_MODEL_MARKER:-UD-IQ3_XXS} shard into ${dir}"
    return 1
  fi
  validate_model_marker "${selected}" || return 1
  validate_single_quant_directory "${dir}" "${selected}" || return 1
  export LOCAL_GGUF_DIR="${dir}" GGUF_MODEL="/models/${relative}"
  printf '[DeepSeek IQ3_XXS] model entry: %s\n' "${selected}"
}

prepare_runtime_local_model() {
  local root="$1" dir selected configured="${GGUF_MODEL:-}"
  if [[ -d /models ]]; then dir=/models; else dir="$(resolve_host_local_gguf_dir "${root}")"; fi
  if [[ -n "${configured}" ]]; then
    [[ "${configured}" = /* ]] || configured="${dir}/${configured#./}"
    [[ -r "${configured}" ]] || { local_model_die "GGUF is not readable: ${configured}"; return 1; }
    selected="${configured}"
  elif selected="$(find_local_gguf_entry "${dir}")"; then :
  elif [[ "${OFFLINE_MODEL_REQUIRED:-1}" = 1 ]]; then
    local_model_die "no ${EXPECTED_MODEL_MARKER:-UD-IQ3_XXS} GGUF found in ${dir}"
    return 1
  else
    export GGUF_MODEL=
    return 0
  fi
  validate_model_marker "${selected}" || return 1
  validate_single_quant_directory "${dir}" "${selected}" || return 1
  export GGUF_MODEL="${selected}"
}
