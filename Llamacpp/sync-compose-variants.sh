#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS=(DeepSeek DeepSeekV4FlashDgxSpark DwarfStar Hy3 Nemotron Qwen)

slug_for() {
  case "$1" in
    DeepSeek) printf '%s' 'deepseek' ;;
    DeepSeekV4FlashDgxSpark) printf '%s' 'deepseekv4flashdgxspark' ;;
    DwarfStar) printf '%s' 'dwarfstar' ;;
    Hy3) printf '%s' 'hy3' ;;
    Nemotron) printf '%s' 'nemotron' ;;
    Qwen) printf '%s' 'qwen' ;;
  esac
}

adapt_paths() {
  sed \
    -e 's#^      context: \.$#      context: ..#' \
    -e 's#^      context: \.\./docker/open-webui-stats$#      context: ../../docker/open-webui-stats#' \
    -e 's#- \.:/#- ../:/#' \
    -e 's#- \./runtime#- ../runtime#' \
    -e 's#- path: \./#- path: ../#'
}

with_ui() {
  awk '
    $0 == "  open-webui-data:" {
      print
      print "    external: true"
      next
    }
    { print }
  '
}

without_ui() {
  awk '
    $0 == "  open-webui:" { skip = 1; next }
    skip && $0 == "volumes:" { skip = 0 }
    !skip { print }
  ' | awk '
    $0 == "  open-webui-data:" { skip = 1; next }
    skip && /^  [^ ]/ { skip = 0 }
    !skip { print }
  ' | sed '${/^volumes:$/d;}'
}

trim_trailing_blank_lines() {
  awk '
    { lines[NR] = $0 }
    END {
      last = NR
      while (last > 0 && lines[last] == "") last--
      for (i = 1; i <= last; i++) print lines[i]
    }
  '
}

render() {
  local model="$1"
  local variant="$2"
  local base="${ROOT_DIR}/${model}/docker-compose.yml"
  local target_dir="${ROOT_DIR}/${model}/${variant}"
  local target="${target_dir}/docker-compose.yml"
  local slug
  slug="$(slug_for "${model}")"
  mkdir -p "${target_dir}"
  ln -sfn ../config.env "${target_dir}/.env"
  {
    printf 'name: %s\n\n' "${slug}"
    if [[ "${variant}" == 'WithUI' ]]; then
      with_ui < "${base}" | adapt_paths
    else
      without_ui < "${base}" | adapt_paths
    fi
  } | trim_trailing_blank_lines > "${target}.tmp"
  mv "${target}.tmp" "${target}"
}

for model in "${MODELS[@]}"; do
  render "${model}" WithUI
  render "${model}" WithoutUI
done

echo 'Synchronized WithUI and WithoutUI compose files.'
