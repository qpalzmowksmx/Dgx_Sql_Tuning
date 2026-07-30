#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 CRITIC_RETUNE_ROUNDS {without-ui|with-ui}" >&2
  exit 2
fi

critic_retune_rounds="$1"
ui_mode="$2"

if [[ ! "${critic_retune_rounds}" =~ ^[0-9]+$ ]]; then
  echo "CRITIC_RETUNE_ROUNDS must be a non-negative integer" >&2
  exit 2
fi

case "${ui_mode}" in
  without-ui|with-ui)
    ;;
  *)
    echo "UI mode must be 'without-ui' or 'with-ui'" >&2
    exit 2
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
QWEN_WITHOUT_UI_START="${REPO_ROOT}/Llamacpp/Qwen/WithoutUI/start.sh"
QWEN_WITH_UI_START="${SCRIPT_DIR}/start_qwen_ui_offline.sh"
DEEPSEEK_START="${REPO_ROOT}/Llamacpp/DeepSeekV4FlashDgxSpark/WithoutUI/start.sh"
HY3_START="${REPO_ROOT}/Llamacpp/Hy3/Reasoning-start.sh"
MODELCTL="${REPO_ROOT}/Llamacpp/modelctl.sh"

cd "${REPO_ROOT}"

source "${SCRIPT_DIR}/_python_runtime.sh"
autorun_refuse_root
autorun_resolve_python "${REPO_ROOT}" "${SCRIPT_DIR}"

if ! "${AUTORUN_PYTHON}" -c "import oracledb" >/dev/null 2>&1; then
  echo "Missing dependency: oracledb"
  echo "Install it into the same virtualenv:"
  echo "  \"${AUTORUN_PYTHON}\" -m pip install -r \"${SCRIPT_DIR}/requirements.txt\""
  exit 1
fi

flag_enabled() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Oracle jobs use the API directly. Structured output is forced so the model
# response and saved artifacts follow the JSON contracts without a UI layer.
export API_BASE_URL="${API_BASE_URL-http://localhost:8080/v1}"
export MODEL_NAME="${MODEL_NAME-qwen-sql-tuner}"
export AUTO_MODEL_SWAP="${AUTO_MODEL_SWAP-1}"
export AUTO_STOP_MODELS="${AUTO_STOP_MODELS-1}"
export CRITIC_MODELS="${CRITIC_MODELS-deepseek,hy3}"
export TUNER_STRUCTURED_OUTPUT=1
export CRITIC_STRUCTURED_OUTPUT=1
export CRITIC_DEEPSEEK_STRUCTURED_OUTPUT=1
export CRITIC_HY3_STRUCTURED_OUTPUT=1
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
export TUNER_START_SCRIPT="${QWEN_WITHOUT_UI_START}"
export CRITIC_DEEPSEEK_START_SCRIPT="${CRITIC_DEEPSEEK_START_SCRIPT-${DEEPSEEK_START}}"
export CRITIC_HY3_START_SCRIPT="${CRITIC_HY3_START_SCRIPT-${HY3_START}}"
export MODEL_START_TIMEOUT_SEC="${MODEL_START_TIMEOUT_SEC-7200}"
export TUNER_HEARTBEAT_SEC="${TUNER_HEARTBEAT_SEC-15}"
export CRITIC_HEARTBEAT_SEC="${CRITIC_HEARTBEAT_SEC-15}"
export TUNER_TIMEOUT_SEC="${TUNER_TIMEOUT_SEC-10800}"
export TUNER_API_ATTEMPTS="${TUNER_API_ATTEMPTS-2}"
export CRITIC_TIMEOUT_SEC="${CRITIC_TIMEOUT_SEC-1800}"
export CRITIC_API_ATTEMPTS="${CRITIC_API_ATTEMPTS-2}"
export CRITIC_DEEPSEEK_API_BASE_URL="${CRITIC_DEEPSEEK_API_BASE_URL-http://localhost:8080/v1}"
export CRITIC_DEEPSEEK_MODEL_NAME="${CRITIC_DEEPSEEK_MODEL_NAME-deepseek-v4-flash-iq3-xxs}"
export CRITIC_DEEPSEEK_REQUEST_STYLE="${CRITIC_DEEPSEEK_REQUEST_STYLE-deepseek_v4}"
export CRITIC_DEEPSEEK_TEMPERATURE="${CRITIC_DEEPSEEK_TEMPERATURE-1.0}"
export CRITIC_DEEPSEEK_TOP_P="${CRITIC_DEEPSEEK_TOP_P-1.0}"
export CRITIC_DEEPSEEK_TOP_K="${CRITIC_DEEPSEEK_TOP_K-0}"
export CRITIC_DEEPSEEK_MIN_P="${CRITIC_DEEPSEEK_MIN_P-0.0}"
export CRITIC_DEEPSEEK_PRESENCE_PENALTY="${CRITIC_DEEPSEEK_PRESENCE_PENALTY-0.0}"
export CRITIC_DEEPSEEK_FREQUENCY_PENALTY="${CRITIC_DEEPSEEK_FREQUENCY_PENALTY-0.0}"
export CRITIC_DEEPSEEK_REPETITION_PENALTY="${CRITIC_DEEPSEEK_REPETITION_PENALTY-1.0}"
export CRITIC_DEEPSEEK_SEED="${CRITIC_DEEPSEEK_SEED-42}"
export CRITIC_DEEPSEEK_THINKING_MODE="${CRITIC_DEEPSEEK_THINKING_MODE-thinking}"
export CRITIC_DEEPSEEK_MAX_TOKENS="${CRITIC_DEEPSEEK_MAX_TOKENS-4096}"
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

if [[ "${ui_mode}" == "with-ui" ]]; then
  export TUNER_START_SCRIPT="${QWEN_WITH_UI_START}"
fi

leave_qwen_ui_running=0

shutdown_models() {
  local exit_code=$?
  trap - EXIT
  if [[ "${leave_qwen_ui_running}" != "1" ]] && flag_enabled "${AUTO_STOP_MODELS}"; then
    echo "[AutorunEnum] stopping all Llamacpp model containers for idle standby"
    "${MODELCTL}" stop || echo "[AutorunEnum] warning: model shutdown reported an error" >&2
  fi
  exit "${exit_code}"
}

trap shutdown_models EXIT

# Start from a known model state. This also removes an already-running
# Open WebUI container before either structured Oracle path begins.
if flag_enabled "${AUTO_MODEL_SWAP}"; then
  echo "[AutorunEnum] clearing the previous Llamacpp model state"
  "${MODELCTL}" stop
fi

ARGS=(
  "${SCRIPT_DIR}/main.py"
  --mode oracle
  --tuner "${TUNER:-auto}"
  --workspace "${WORKSPACE:-${REPO_ROOT}/workspace}"
  --collect-hours "${COLLECT_HOURS:-24}"
  --query-limit "${QUERY_LIMIT:-50}"
  --min-executions "${MIN_EXECUTIONS:-1}"
  --max-retry "${MAX_RETRY:-2}"
  --critic-retune-rounds "${critic_retune_rounds}"
  --validation-row-limit "${VALIDATION_ROW_LIMIT:-100000}"
  --critics "${CRITICS:-}"
)

# Optional flags are off by default.
# EXECUTE_BENCHMARK=1 also enables Oracle parse/explain/sample validation.
if flag_enabled "${EXECUTE_BENCHMARK:-}"; then
  ARGS+=(--execute-benchmark)
fi

# Run parse/explain/sample validation without the full benchmark.
if flag_enabled "${ORACLE_VALIDATE:-}"; then
  ARGS+=(--oracle-validate)
fi

if flag_enabled "${SKIP_CRITICS:-}"; then
  ARGS+=(--skip-critics)
fi

if flag_enabled "${MANUAL_MODEL_SWAP:-}"; then
  ARGS+=(--manual-model-swap)
fi

echo "[AutorunEnum] repository root: ${REPO_ROOT}"
echo "[AutorunEnum] workspace: ${WORKSPACE:-${REPO_ROOT}/workspace}"
echo "[AutorunEnum] model output: structured JSON"
echo "[AutorunEnum] critic feedback retune rounds: ${critic_retune_rounds}"

"${AUTORUN_PYTHON}" "${ARGS[@]}"

if [[ "${ui_mode}" == "with-ui" ]]; then
  echo "[AutorunEnum] Oracle run completed; starting Qwen with Open WebUI"
  "${QWEN_WITH_UI_START}"
  leave_qwen_ui_running=1
  echo "[AutorunEnum] Open WebUI: http://127.0.0.1:3000"
fi
