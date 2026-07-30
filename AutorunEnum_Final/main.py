from __future__ import annotations

import argparse
import os
from pathlib import Path

from Autorun import PipelineState
from PipelineManager import PipelineManager


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
DEFAULT_WORKSPACE = REPO_ROOT / "workspace"
DEFAULT_SOURCE_DIR = SCRIPT_DIR.parent / "Query"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the AutorunEnum SQL tuning pipeline.")
    parser.add_argument(
        "--mode",
        choices=["oracle", "files"],
        default="oracle",
        help="oracle: collect from V$SQL, files: collect from --source",
    )
    parser.add_argument(
        "--tuner",
        choices=["auto", "llm", "local"],
        default="auto",
        help="auto uses LLM when API_BASE_URL is set, otherwise local draft",
    )
    parser.add_argument(
        "--workspace",
        type=Path,
        default=DEFAULT_WORKSPACE,
        help=f"workspace directory (default: {DEFAULT_WORKSPACE})",
    )
    parser.add_argument(
        "--source",
        type=Path,
        action="append",
        default=None,
        help=(
            "source SQL directory; repeat for multiple directories. "
            f"Directories are scanned recursively (default: {DEFAULT_SOURCE_DIR})"
        ),
    )
    parser.add_argument(
        "--max-retry",
        type=int,
        default=2,
        help="maximum automatic retry count",
    )
    parser.add_argument(
        "--critic-retune-rounds",
        type=int,
        default=0,
        help="Qwen retuning rounds performed after critic feedback",
    )
    parser.add_argument(
        "--collect-hours",
        type=int,
        default=24,
        help="Oracle V$SQL collection window in hours",
    )
    parser.add_argument(
        "--query-limit",
        type=int,
        default=50,
        help="maximum number of SQL statements to collect",
    )
    parser.add_argument(
        "--min-executions",
        type=int,
        default=1,
        help="minimum executions in V$SQL",
    )
    parser.add_argument(
        "--improvement-threshold-pct",
        type=float,
        default=5.0,
        help="minimum elapsed-time improvement percentage",
    )
    parser.add_argument(
        "--execute-benchmark",
        action="store_true",
        help="execute SELECT SQL against Oracle for original/tuned comparison",
    )
    parser.add_argument(
        "--benchmark-row-limit",
        type=int,
        default=50,
        help="row limit used when --execute-benchmark is enabled",
    )
    parser.add_argument(
        "--oracle-validate",
        action="store_true",
        help="run Oracle parse/explain/sample validation before benchmark",
    )
    parser.add_argument(
        "--validation-row-limit",
        type=int,
        default=100000,
        help="maximum rows used for complete original/tuned result comparison",
    )
    parser.add_argument(
        "--critics",
        default="",
        help="comma-separated critic aliases, for example: deepseek,nemotron",
    )
    parser.add_argument(
        "--skip-critics",
        action="store_true",
        help="disable critic review even when CRITIC_MODELS is configured",
    )
    parser.add_argument(
        "--manual-model-swap",
        action="store_true",
        help="pause before Qwen/critic calls so one DGX can load one large model at a time",
    )
    return parser.parse_args()


def run_pipeline(manager: PipelineManager) -> PipelineManager:
    state = PipelineState.COLLECT_SQL
    retry_count = 0
    critic_retune_count = 0
    feedback_retune_active = False

    while True:
        print(f"[STATE] {state.name}")

        if state == PipelineState.COLLECT_SQL:
            manager.collect_sql()
            state = PipelineState.COLLECT_METADATA

        elif state == PipelineState.COLLECT_METADATA:
            manager.collect_metadata()
            state = PipelineState.BUILD_RAG

        elif state == PipelineState.BUILD_RAG:
            manager.build_rag()
            state = PipelineState.ANALYZE

        elif state == PipelineState.ANALYZE:
            manager.analyze_sql()
            state = PipelineState.TUNE

        elif state == PipelineState.TUNE:
            manager.tune_sql()
            if feedback_retune_active:
                feedback_retune_active = False
                # The final Qwen rewrite must be reviewed again. Otherwise Qwen can
                # introduce a new semantic error after both critics have approved
                # the previous candidate.
                state = PipelineState.CRITIQUE
            else:
                state = PipelineState.CRITIQUE

        elif state == PipelineState.CRITIQUE:
            manager.critique_tuned_sql()
            if manager.should_retune_after_critique(critic_retune_count):
                critic_retune_count += 1
                manager.prepare_critic_retune(critic_retune_count)
                feedback_retune_active = True
                state = PipelineState.ANALYZE
            else:
                state = PipelineState.VALIDATE_ORACLE

        elif state == PipelineState.VALIDATE_ORACLE:
            manager.validate_oracle()
            state = PipelineState.BENCHMARK

        elif state == PipelineState.BENCHMARK:
            manager.benchmark()
            state = PipelineState.VERIFY

        elif state == PipelineState.VERIFY:
            if manager.is_improved():
                state = PipelineState.SUCCESS
            else:
                state = PipelineState.REANALYZE

        elif state == PipelineState.REANALYZE:
            if retry_count >= manager.max_retry:
                state = PipelineState.WAIT_USER
            else:
                retry_count += 1
                manager.retry_jobs()
                state = PipelineState.ANALYZE

        elif state == PipelineState.WAIT_USER:
            manager.notify_user()
            manager.wait_user()
            state = PipelineState.FAILED

        elif state == PipelineState.SUCCESS:
            manager.move_success()
            break

        elif state == PipelineState.FAILED:
            manager.move_failed()
            break

    return manager


def main() -> None:
    allow_root = os.getenv("ALLOW_ROOT_PIPELINE", "0").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }
    if getattr(os, "geteuid", lambda: -1)() == 0 and not allow_root:
        raise SystemExit(
            "Do not run AutorunEnum with sudo. Activate the repository virtualenv "
            "and run as the normal user. Set ALLOW_ROOT_PIPELINE=1 only for an "
            "intentional root-only recovery run."
        )
    # SQL, schema metadata, validation samples and credentials are sensitive.
    # New runtime files/directories therefore default to 0600/0700.
    os.umask(0o077)
    args = parse_args()
    source_dirs = [path.resolve() for path in (args.source or [DEFAULT_SOURCE_DIR])]
    manager = PipelineManager(
        workspace=args.workspace.resolve(),
        source_dir=source_dirs,
        mode=args.mode,
        tuner=args.tuner,
        max_retry=args.max_retry,
        critic_retune_rounds=args.critic_retune_rounds,
        collect_hours=args.collect_hours,
        query_limit=args.query_limit,
        min_executions=args.min_executions,
        improvement_threshold_pct=args.improvement_threshold_pct,
        execute_benchmark=args.execute_benchmark,
        benchmark_row_limit=args.benchmark_row_limit,
        oracle_validate=args.oracle_validate,
        validation_row_limit=args.validation_row_limit,
        critics=args.critics,
        skip_critics=args.skip_critics,
        manual_model_swap=args.manual_model_swap,
    )
    try:
        run_pipeline(manager)
        manager.print_summary()
    finally:
        manager.close()


if __name__ == "__main__":
    main()
