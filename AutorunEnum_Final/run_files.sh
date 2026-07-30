#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEEPSEEK_DIR="${REPO_ROOT}/Llamacpp/DeepSeekV4FlashDgxSpark"
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

# File mode is the offline/manual-SQL path. Explicit caller values still win.
export ORACLE_VALIDATE="${ORACLE_VALIDATE-0}"
export REQUIRE_ORACLE_VALIDATION="${REQUIRE_ORACLE_VALIDATION-0}"
export EXECUTE_BENCHMARK="${EXECUTE_BENCHMARK-0}"
export CRITIC_MODELS="${CRITIC_MODELS-deepseek,hy3}"
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
export CRITIC_DEEPSEEK_START_SCRIPT="${CRITIC_DEEPSEEK_START_SCRIPT-${DEEPSEEK_START}}"
export TUNER_HEARTBEAT_SEC="${TUNER_HEARTBEAT_SEC-15}"
export TUNER_TIMEOUT_SEC="${TUNER_TIMEOUT_SEC-10800}"
export TUNER_API_ATTEMPTS="${TUNER_API_ATTEMPTS-2}"
export MODEL_START_TIMEOUT_SEC="${MODEL_START_TIMEOUT_SEC-7200}"
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
export CRITIC_DEEPSEEK_STRUCTURED_OUTPUT="${CRITIC_DEEPSEEK_STRUCTURED_OUTPUT-1}"
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

shutdown_models() {
  local exit_code=$?
  if [[ "${AUTO_STOP_MODELS}" == "1" ]]; then
    echo "[AutorunEnum] stopping all Llamacpp model containers for idle standby"
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

echo "[AutorunEnum] repository root: ${REPO_ROOT}"
echo "[AutorunEnum] workspace: ${WORKSPACE:-${REPO_ROOT}/workspace}"
echo "[AutorunEnum] flow: Qwen initial tune -> DeepSeek critique -> Hy3 IQ1_M critique -> Qwen final rewrite -> idle standby"
for ((index=0; index<${#ARGS[@]}; index++)); do
  if [[ "${ARGS[index]}" == "--source" ]]; then
    echo "[AutorunEnum] SQL source: ${ARGS[index+1]} (recursive)"
  fi
done

"${AUTORUN_PYTHON}" "${ARGS[@]}"
