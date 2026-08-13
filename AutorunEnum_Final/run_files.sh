#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEEPSEEK_DIR="${REPO_ROOT}/Llamacpp/DeepSeek_V4_Flash_0731_DSpark"
DEEPSEEK_START="${DEEPSEEK_DIR}/WithoutUI/start.sh"
QWEN_DIR="${REPO_ROOT}/Llamacpp/Qwen"
QWEN_START="${QWEN_DIR}/WithoutUI/start.sh"
HY3_DIR="${REPO_ROOT}/Llamacpp/Hy3"
HY3_START="${HY3_DIR}/Reasoning-start.sh"
MODELCTL="${REPO_ROOT}/Llamacpp/modelctl.sh"

# All relative paths and output are resolved from the LLM-sql repository root.
cd "${REPO_ROOT}"

source "${SCRIPT_DIR}/_python_runtime.sh"
autorun_refuse_root
autorun_resolve_python "${REPO_ROOT}" "${SCRIPT_DIR}"

# File mode tries Oracle validation when the database is reachable. A connection
# or driver failure falls back to model-only processing. Set
# REQUIRE_ORACLE_VALIDATION=1 when the run must fail closed instead.
export ORACLE_VALIDATE="${ORACLE_VALIDATE-1}"
export REQUIRE_ORACLE_VALIDATION="${REQUIRE_ORACLE_VALIDATION-0}"
export EXECUTE_BENCHMARK="${EXECUTE_BENCHMARK-0}"
export CRITIC_MODELS="${CRITIC_MODELS-hy3}"
export MANUAL_MODEL_SWAP="${MANUAL_MODEL_SWAP-0}"
export AUTO_MODEL_SWAP="${AUTO_MODEL_SWAP-1}"
export AUTO_STOP_MODELS="${AUTO_STOP_MODELS-1}"
export API_BASE_URL="${API_BASE_URL-http://localhost:8080/v1}"
export MODEL_NAME="${MODEL_NAME-qwen-sql-tuner}"
export TUNER_START_SCRIPT="${TUNER_START_SCRIPT-${QWEN_START}}"
export QWEN_CTX_SIZE="${QWEN_CTX_SIZE-131072}"
export QWEN_LLAMA_SERVER_EXTRA_ARGS="${QWEN_LLAMA_SERVER_EXTRA_ARGS---metrics --reasoning on --reasoning-budget -1 --reasoning-format deepseek}"
export TUNER_TEMPERATURE="${TUNER_TEMPERATURE-0.6}"
export TUNER_TOP_P="${TUNER_TOP_P-0.95}"
export TUNER_TOP_K="${TUNER_TOP_K-20}"
export TUNER_MIN_P="${TUNER_MIN_P-0.0}"
export TUNER_PRESENCE_PENALTY="${TUNER_PRESENCE_PENALTY-0.0}"
export TUNER_FREQUENCY_PENALTY="${TUNER_FREQUENCY_PENALTY-0.0}"
export TUNER_REPETITION_PENALTY="${TUNER_REPETITION_PENALTY-1.0}"
export TUNER_SEED="${TUNER_SEED-42}"
export TUNER_THINKING="${TUNER_THINKING-1}"
export TUNER_REASONING_FORMAT="${TUNER_REASONING_FORMAT-deepseek}"
export TUNER_MAX_TOKENS="${TUNER_MAX_TOKENS-81920}"
export TUNER_CONTEXT_SIZE="${TUNER_CONTEXT_SIZE-${QWEN_CTX_SIZE}}"
export TUNER_CONTEXT_SAFETY_TOKENS="${TUNER_CONTEXT_SAFETY_TOKENS-4096}"
export TUNER_MIN_OUTPUT_TOKENS="${TUNER_MIN_OUTPUT_TOKENS-2048}"
export TUNER_CACHE_PROMPT="${TUNER_CACHE_PROMPT-1}"
export FINAL_WRITER_ENABLED="${FINAL_WRITER_ENABLED-1}"
export FINAL_WRITER_START_SCRIPT="${FINAL_WRITER_START_SCRIPT-${DEEPSEEK_START}}"
export FINAL_WRITER_API_BASE_URL="${FINAL_WRITER_API_BASE_URL-http://localhost:8080/v1}"
export FINAL_WRITER_LABEL="${FINAL_WRITER_LABEL-DeepSeek 0731 DS4 SSD streaming}"
export FINAL_WRITER_MODEL_NAME="${FINAL_WRITER_MODEL_NAME-deepseek-v4-flash}"
export FINAL_WRITER_REQUEST_STYLE="${FINAL_WRITER_REQUEST_STYLE-ds4}"
export FINAL_WRITER_TEMPERATURE="${FINAL_WRITER_TEMPERATURE-0}"
export FINAL_WRITER_TOP_P="${FINAL_WRITER_TOP_P-1.0}"
export FINAL_WRITER_TOP_K="${FINAL_WRITER_TOP_K-0}"
export FINAL_WRITER_MIN_P="${FINAL_WRITER_MIN_P-0.0}"
export FINAL_WRITER_PRESENCE_PENALTY="${FINAL_WRITER_PRESENCE_PENALTY-0.0}"
export FINAL_WRITER_FREQUENCY_PENALTY="${FINAL_WRITER_FREQUENCY_PENALTY-0.0}"
export FINAL_WRITER_REPETITION_PENALTY="${FINAL_WRITER_REPETITION_PENALTY-1.0}"
export FINAL_WRITER_SEED="${FINAL_WRITER_SEED-42}"
export FINAL_WRITER_THINKING_MODE="${FINAL_WRITER_THINKING_MODE-thinking}"
export FINAL_WRITER_REASONING_EFFORT="${FINAL_WRITER_REASONING_EFFORT-max}"
export FINAL_WRITER_AGENT_MODE="${FINAL_WRITER_AGENT_MODE-minimal}"
export FINAL_WRITER_MAX_TOKENS="${FINAL_WRITER_MAX_TOKENS-16384}"
export FINAL_WRITER_CONTEXT_SIZE="${FINAL_WRITER_CONTEXT_SIZE-32768}"
export FINAL_WRITER_CONTEXT_SAFETY_TOKENS="${FINAL_WRITER_CONTEXT_SAFETY_TOKENS-2048}"
export FINAL_WRITER_MIN_OUTPUT_TOKENS="${FINAL_WRITER_MIN_OUTPUT_TOKENS-2048}"
export FINAL_WRITER_CACHE_PROMPT="${FINAL_WRITER_CACHE_PROMPT-1}"
export FINAL_WRITER_STRUCTURED_OUTPUT="${FINAL_WRITER_STRUCTURED_OUTPUT-0}"
export FINAL_WRITER_TIMEOUT_SEC="${FINAL_WRITER_TIMEOUT_SEC-10800}"
export FINAL_WRITER_API_ATTEMPTS="${FINAL_WRITER_API_ATTEMPTS-2}"
export FINAL_WRITER_HEARTBEAT_SEC="${FINAL_WRITER_HEARTBEAT_SEC-15}"
export CRITIC_DEEPSEEK_START_SCRIPT="${CRITIC_DEEPSEEK_START_SCRIPT-${DEEPSEEK_START}}"
export TUNER_HEARTBEAT_SEC="${TUNER_HEARTBEAT_SEC-15}"
export TUNER_TIMEOUT_SEC="${TUNER_TIMEOUT_SEC-10800}"
export TUNER_API_ATTEMPTS="${TUNER_API_ATTEMPTS-2}"
export MODEL_START_TIMEOUT_SEC="${MODEL_START_TIMEOUT_SEC-7200}"
export CRITIC_DEEPSEEK_API_BASE_URL="${CRITIC_DEEPSEEK_API_BASE_URL-http://localhost:8080/v1}"
export CRITIC_DEEPSEEK_MODEL_NAME="${CRITIC_DEEPSEEK_MODEL_NAME-deepseek-v4-flash}"
export CRITIC_DEEPSEEK_REQUEST_STYLE="${CRITIC_DEEPSEEK_REQUEST_STYLE-ds4}"
export CRITIC_DEEPSEEK_TEMPERATURE="${CRITIC_DEEPSEEK_TEMPERATURE-0}"
export CRITIC_DEEPSEEK_TOP_P="${CRITIC_DEEPSEEK_TOP_P-1.0}"
export CRITIC_DEEPSEEK_TOP_K="${CRITIC_DEEPSEEK_TOP_K-0}"
export CRITIC_DEEPSEEK_MIN_P="${CRITIC_DEEPSEEK_MIN_P-0.0}"
export CRITIC_DEEPSEEK_PRESENCE_PENALTY="${CRITIC_DEEPSEEK_PRESENCE_PENALTY-0.0}"
export CRITIC_DEEPSEEK_FREQUENCY_PENALTY="${CRITIC_DEEPSEEK_FREQUENCY_PENALTY-0.0}"
export CRITIC_DEEPSEEK_REPETITION_PENALTY="${CRITIC_DEEPSEEK_REPETITION_PENALTY-1.0}"
export CRITIC_DEEPSEEK_SEED="${CRITIC_DEEPSEEK_SEED-42}"
export CRITIC_DEEPSEEK_THINKING_MODE="${CRITIC_DEEPSEEK_THINKING_MODE-thinking}"
export CRITIC_DEEPSEEK_REASONING_EFFORT="${CRITIC_DEEPSEEK_REASONING_EFFORT-max}"
export CRITIC_DEEPSEEK_MAX_TOKENS="${CRITIC_DEEPSEEK_MAX_TOKENS-4096}"
export CRITIC_DEEPSEEK_STRUCTURED_OUTPUT="${CRITIC_DEEPSEEK_STRUCTURED_OUTPUT-0}"
export CRITIC_HY3_START_SCRIPT="${CRITIC_HY3_START_SCRIPT-${HY3_START}}"
export CRITIC_HY3_API_BASE_URL="${CRITIC_HY3_API_BASE_URL-http://localhost:8080/v1}"
export CRITIC_HY3_MODEL_NAME="${CRITIC_HY3_MODEL_NAME-hy3-iq1-m-mtp}"
export CRITIC_HY3_REQUEST_STYLE="${CRITIC_HY3_REQUEST_STYLE-hy3}"
export CRITIC_HY3_TEMPERATURE="${CRITIC_HY3_TEMPERATURE-0.9}"
export CRITIC_HY3_TOP_P="${CRITIC_HY3_TOP_P-1.0}"
export CRITIC_HY3_TOP_K="${CRITIC_HY3_TOP_K-0}"
export CRITIC_HY3_MIN_P="${CRITIC_HY3_MIN_P-0.0}"
export CRITIC_HY3_PRESENCE_PENALTY="${CRITIC_HY3_PRESENCE_PENALTY-0.0}"
export CRITIC_HY3_FREQUENCY_PENALTY="${CRITIC_HY3_FREQUENCY_PENALTY-0.0}"
export CRITIC_HY3_REPETITION_PENALTY="${CRITIC_HY3_REPETITION_PENALTY-1.0}"
export CRITIC_HY3_SEED="${CRITIC_HY3_SEED-42}"
export CRITIC_HY3_REASONING_EFFORT="${CRITIC_HY3_REASONING_EFFORT-high}"
export CRITIC_HY3_MAX_TOKENS="${CRITIC_HY3_MAX_TOKENS-4096}"
export CRITIC_HY3_STRUCTURED_OUTPUT="${CRITIC_HY3_STRUCTURED_OUTPUT-1}"
export CRITIC_API_ATTEMPTS="${CRITIC_API_ATTEMPTS-2}"
export CRITIC_HEARTBEAT_SEC="${CRITIC_HEARTBEAT_SEC-15}"
export MODEL_LAUNCH_TIMEOUT_SEC="${MODEL_LAUNCH_TIMEOUT_SEC-7500}"

flag_enabled() {
  local normalized
  normalized="$(printf '%s' "${1}" | tr '[:upper:]' '[:lower:]')"
  case "${normalized}" in
    1|true|yes|on) return 0 ;;
    0|false|no|off|"") return 1 ;;
    *)
      echo "[AutorunEnum] invalid boolean value: ${1}" >&2
      return 2
      ;;
  esac
}

if flag_enabled "${ORACLE_VALIDATE}" || flag_enabled "${EXECUTE_BENCHMARK}"; then
  if ! "${AUTORUN_PYTHON}" -c 'import oracledb' >/dev/null 2>&1; then
    if flag_enabled "${REQUIRE_ORACLE_VALIDATION}"; then
      echo "[AutorunEnum] Oracle validation requires python-oracledb in the selected virtual environment." >&2
      echo "[AutorunEnum] selected Python: ${AUTORUN_PYTHON}" >&2
      echo "[AutorunEnum] install with: ${AUTORUN_PYTHON} -m pip install -r ${SCRIPT_DIR}/requirements.txt" >&2
      exit 1
    fi
    echo "[AutorunEnum] warning: python-oracledb is unavailable; continuing without Oracle validation or benchmark." >&2
    export ORACLE_VALIDATE=0
    export EXECUTE_BENCHMARK=0
  else
    preflight_args=("${SCRIPT_DIR}/oracle_preflight.py" --mode files --validation)
    if ! "${AUTORUN_PYTHON}" "${preflight_args[@]}"; then
      if flag_enabled "${REQUIRE_ORACLE_VALIDATION}"; then
        echo "[AutorunEnum] Oracle is required; stopping before model startup." >&2
        exit 1
      fi
      echo "[AutorunEnum] warning: Oracle is unavailable; continuing with model-only processing." >&2
      export ORACLE_VALIDATE=0
      export EXECUTE_BENCHMARK=0
    fi
  fi
fi

shutdown_models() {
  local exit_code=$?
  if [[ "${AUTO_STOP_MODELS}" == "1" ]]; then
    echo "[AutorunEnum] stopping all Llamacpp model containers for idle standby"
    "${DEEPSEEK_DIR}/WithoutUI/stop.sh" >/dev/null 2>&1 || \
      echo "[AutorunEnum] warning: DS4 shutdown reported an error" >&2
    "${MODELCTL}" stop || echo "[AutorunEnum] warning: model shutdown reported an error" >&2
  fi
  return "${exit_code}"
}

trap shutdown_models EXIT

# Query is the default recursive manual-input tree. Add independent roots with
# SOURCE_DIRS='Query:AnotherDirectory:/absolute/path'. SOURCE_DIR remains a
# compatible single-directory shortcut.
if [[ -n "${SOURCE_DIRS:-}" ]]; then
  source_spec="${SOURCE_DIRS}"
elif [[ -n "${SOURCE_DIR:-}" ]]; then
  source_spec="${SOURCE_DIR}"
else
  source_spec="Query"
fi

IFS=':' read -r -a source_entries <<< "${source_spec}"
ARGS=(
  "${SCRIPT_DIR}/main.py"
  --mode files
  --tuner "${TUNER:-llm}"
  --workspace "${WORKSPACE:-${REPO_ROOT}/workspace}"
  --max-retry "${MAX_RETRY:-0}"
  --critic-retune-rounds "${CRITIC_RETUNE_ROUNDS:-1}"
)

for source_entry in "${source_entries[@]}"; do
  [[ -n "${source_entry}" ]] || continue
  if [[ "${source_entry}" = /* ]]; then
    source_path="${source_entry}"
  else
    source_path="${REPO_ROOT}/${source_entry#./}"
  fi
  ARGS+=(--source "${source_path}")
done

if flag_enabled "${ORACLE_VALIDATE}"; then
  ARGS+=(--oracle-validate)
fi
if flag_enabled "${EXECUTE_BENCHMARK}"; then
  ARGS+=(--execute-benchmark)
fi

echo "[AutorunEnum] repository root: ${REPO_ROOT}"
echo "[AutorunEnum] workspace: ${WORKSPACE:-${REPO_ROOT}/workspace}"
echo "[AutorunEnum] flow: Qwen draft -> Hy3 critique -> DeepSeek 0731 DS4 final rewrite -> Hy3 final review -> idle standby"
echo "[AutorunEnum] Oracle validation: ${ORACLE_VALIDATE} (required=${REQUIRE_ORACLE_VALIDATION})"
echo "[AutorunEnum] execution benchmark: ${EXECUTE_BENCHMARK}"
for ((index=0; index<${#ARGS[@]}; index++)); do
  if [[ "${ARGS[index]}" == "--source" ]]; then
    echo "[AutorunEnum] SQL source: ${ARGS[index+1]} (recursive)"
  fi
done

"${AUTORUN_PYTHON}" "${ARGS[@]}"
