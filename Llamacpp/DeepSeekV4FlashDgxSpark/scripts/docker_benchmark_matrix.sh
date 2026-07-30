#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source ./scripts/common.sh
ensure_config
load_config

require_cmd tee
./scripts/01_preflight.sh docker

if compose ps --status running --services | grep -q '^deepseek-v4-flash-dgx-spark$'; then
  echo "Stop the running server first: docker compose --env-file config.env down" >&2
  exit 1
fi

head_ref="${LLAMA_CPP_REF}"
run_id="$(date -u +%Y%m%dT%H%M%SZ)"
output_dir="${BENCH_RESULTS_DIR}/${run_id}-docker"
mkdir -p "${output_dir}"
printf 'label\tref\tmmap\top_min_batch\tresult\n' > "${output_dir}/runs.tsv"

labels=(base pre_cuda head head_mmap head_offload1)
refs=(
  "${LLAMA_CPP_BASE_REF}"
  "${LLAMA_CPP_PRE_CUDA_REF}"
  "${head_ref}"
  "${head_ref}"
  "${head_ref}"
)
mmaps=(0 0 0 1 0)
op_min_batches=(32 32 32 32 1)

current_ref=""
head_verified=0
restore_head_image() {
  if [[ -n "${current_ref}" && "${current_ref}" != "${head_ref}" ]]; then
    echo "Restoring optimized HEAD image after interrupted matrix."
    (export LLAMA_CPP_REF="${head_ref}"; compose build) || true
  fi
}
trap restore_head_image EXIT

for ((i = 0; i < ${#labels[@]}; i++)); do
  label="${labels[${i}]}"
  ref="${refs[${i}]}"
  mmap_mode="${mmaps[${i}]}"
  op_min_batch="${op_min_batches[${i}]}"

  if [[ "${current_ref}" != "${ref}" ]]; then
    echo "Building ${label}: ${ref}"
    current_ref="${ref}"
    (export LLAMA_CPP_REF="${ref}"; compose build)
  fi
  if [[ "${ref}" == "${head_ref}" && "${head_verified}" == "0" ]]; then
    compose run --rm --no-deps -T \
      --entrypoint /opt/dsv4-dgx-wrapper/scripts/06_verify_backend_ops.sh \
      deepseek-v4-flash-dgx-spark
    head_verified=1
  fi

  result_file="${output_dir}/${label}.md"
  metadata_file="${output_dir}/${label}.metadata.txt"
  write_benchmark_metadata "${metadata_file}" "${ref}" "${mmap_mode}" "${op_min_batch}"
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "${label}" "${ref}" "${mmap_mode}" "${op_min_batch}" "$(basename "${result_file}")" \
    >> "${output_dir}/runs.tsv"

  echo "Running ${label}: mmap=${mmap_mode}, op_min_batch=${op_min_batch}"
  set +e
  compose run --rm --no-deps -T \
    -e LLAMA_CPP_REF="${ref}" \
    -e USE_MMAP="${mmap_mode}" \
    -e GGML_OP_OFFLOAD_MIN_BATCH="${op_min_batch}" \
    --entrypoint /opt/dsv4-dgx-wrapper/scripts/05_benchmark.sh \
    deepseek-v4-flash-dgx-spark 2>&1 | tee "${result_file}"
  bench_status="${PIPESTATUS[0]}"
  set -e
  if [[ "${bench_status}" != "0" ]]; then
    echo "Benchmark failed for ${label}; results kept in ${output_dir}." >&2
    exit "${bench_status}"
  fi
done

summary_file="${output_dir}/generation-summary.md"
{
  printf '# Generation benchmark summary\n\n'
  for label in "${labels[@]}"; do
    printf '## %s\n\n' "${label}"
    grep -E '\|[[:space:]]+tg[0-9]+([[:space:]]+@[[:space:]]+d[0-9]+)?[[:space:]]+\|' \
      "${output_dir}/${label}.md" || true
    printf '\n'
  done
} > "${summary_file}"

trap - EXIT
echo "Benchmark matrix complete: ${output_dir}"
echo "Generation summary: ${summary_file}"
