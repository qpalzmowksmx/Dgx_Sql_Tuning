#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
load_config

TEST_BIN="${LLAMA_CPP_DIR}/build/bin/test-backend-ops"
if [[ ! -x "${TEST_BIN}" ]]; then
  echo "Missing test-backend-ops: ${TEST_BIN}" >&2
  exit 1
fi

export CUDA_VISIBLE_DEVICES
configure_cuda_runtime

all_output="$("${TEST_BIN}" test \
  -b CUDA0 \
  -o SINKHORN_NORM,DSV4_HC_WEIGHTED_SUM,DSV4_HC_EXPAND 2>&1)" || {
  printf '%s\n' "${all_output}"
  exit 1
}
printf '%s\n' "${all_output}"
if grep -qi 'not supported' <<< "${all_output}"; then
  echo "At least one fused DeepSeek V4 CUDA test was reported as unsupported." >&2
  exit 1
fi

decode_output="$("${TEST_BIN}" test \
  -b CUDA0 \
  -o DSV4_HC_WEIGHTED_SUM,DSV4_HC_EXPAND \
  -p 'n_tokens=1$' 2>&1)" || {
  printf '%s\n' "${decode_output}"
  exit 1
}
printf '%s\n' "${decode_output}"

if grep -qi 'not supported' <<< "${decode_output}"; then
  echo "Single-token DSV4 CUDA test was reported as unsupported." >&2
  exit 1
fi
if ! grep -Eq '4/4 tests passed' <<< "${decode_output}"; then
  echo "Expected four single-token DSV4 CUDA reference comparisons." >&2
  exit 1
fi

echo "Fused DeepSeek V4 CUDA backend ops, including four single-token cases, passed."
