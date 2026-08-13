from __future__ import annotations

import fcntl
import json
import hashlib
import os
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from EnumAuto import QueryStatus
from QueryJob import QueryJob


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
DEFAULT_TUNER_PROMPT_PATH = REPO_ROOT / "txt" / "MasteryPrompt.txt"
DEFAULT_CRITIC_PROMPT_PATH = REPO_ROOT / "txt" / "CriticPrompt.txt"
DEFAULT_DEEPSEEK_AGENT_PROMPT_PATH = (
    REPO_ROOT / "txt" / "DeepSeekV4Flash0731CodeAgentMaxPrompt.txt"
)
DEFAULT_TUNER_RESPONSE_SCHEMA_PATH = REPO_ROOT / "contracts" / "tuner_response.schema.json"
DEFAULT_CRITIC_RESPONSE_SCHEMA_PATH = REPO_ROOT / "contracts" / "critic_response.schema.json"
DEFAULT_DB_CATALOG_SCHEMA_PATH = REPO_ROOT / "contracts" / "db_catalog.schema.json"
DEFAULT_DB_QUERY_CONTEXT_SCHEMA_PATH = REPO_ROOT / "contracts" / "query_context.schema.json"
DEFAULT_DB_CATALOG_PATH = REPO_ROOT / "db_context" / "catalog.json"
DEFAULT_DB_QUERY_CONTEXT_DIR = REPO_ROOT / "db_context" / "queries"


class PipelineManager:
    def __init__(
        self,
        workspace: Path,
        source_dir: Path | list[Path] | tuple[Path, ...],
        mode: str = "oracle",
        tuner: str = "auto",
        max_retry: int = 2,
        critic_retune_rounds: int = 0,
        collect_hours: int = 24,
        query_limit: int = 50,
        min_executions: int = 1,
        improvement_threshold_pct: float = 5.0,
        execute_benchmark: bool = False,
        benchmark_row_limit: int = 50,
        oracle_validate: bool = False,
        validation_row_limit: int = 100000,
        critics: str = "",
        skip_critics: bool = False,
        manual_model_swap: bool = False,
    ):
        self.workspace = workspace
        self.workspace.mkdir(parents=True, exist_ok=True, mode=0o700)
        lock_path = self.workspace / ".autorun.lock"
        self._workspace_lock_fd = os.open(
            lock_path,
            os.O_CREAT | os.O_RDWR,
            0o600,
        )
        try:
            fcntl.flock(
                self._workspace_lock_fd,
                fcntl.LOCK_EX | fcntl.LOCK_NB,
            )
        except BlockingIOError as exc:
            os.close(self._workspace_lock_fd)
            self._workspace_lock_fd = -1
            raise RuntimeError(
                f"another AutorunEnum process is already using {self.workspace}"
            ) from exc
        if isinstance(source_dir, Path):
            self.source_dirs = [source_dir]
        else:
            self.source_dirs = list(source_dir)
        self.source_dir = self.source_dirs[0] if self.source_dirs else REPO_ROOT / "Query"
        self.mode = mode
        self.tuner = tuner
        self.max_retry = max_retry
        self.critic_retune_rounds = max(0, critic_retune_rounds)
        self.auto_model_swap = self._env_bool("AUTO_MODEL_SWAP", False)
        self.tuning_round = 0
        self.critique_round = 0
        self.collect_hours = collect_hours
        self.query_limit = query_limit
        self.min_executions = min_executions
        self.improvement_threshold_pct = improvement_threshold_pct
        self.execute_benchmark = execute_benchmark
        self.benchmark_row_limit = benchmark_row_limit
        self.oracle_validate = (
            oracle_validate
            or execute_benchmark
            or self._env_bool("ORACLE_VALIDATE", False)
        )
        self.validation_row_limit = int(self._env("VALIDATION_ROW_LIMIT", str(validation_row_limit)))
        self.store_sample_rows = self._env_bool("STORE_SAMPLE_ROWS", False)
        self.benchmark_mode = self._env("BENCHMARK_MODE", "full").strip().lower()
        if self.benchmark_mode not in {"full", "first_n"}:
            raise ValueError("BENCHMARK_MODE must be full or first_n")
        self.benchmark_repetitions = max(2, int(self._env("BENCHMARK_REPETITIONS", "6")))
        self.oracle_call_timeout_ms = max(1, int(self._env("ORACLE_CALL_TIMEOUT_MS", "60000")))
        self.require_oracle_validation = self._env_bool(
            "REQUIRE_ORACLE_VALIDATION",
            self.oracle_validate,
        )
        self.jobs: list[QueryJob] = []
        self.critics = [] if skip_critics else self._parse_critics(critics)
        self.require_critic_approval = self._env_bool(
            "REQUIRE_CRITIC_APPROVAL",
            bool(self.critics),
        )
        self.manual_model_swap = manual_model_swap or self._env_bool("MANUAL_MODEL_SWAP", False)
        self.tuner_prompt, self.tuner_prompt_meta = self._load_prompt(
            "TUNER_PROMPT_PATH",
            DEFAULT_TUNER_PROMPT_PATH,
            self._default_tuner_prompt(),
        )
        self.critic_prompt, self.critic_prompt_meta = self._load_prompt(
            "CRITIC_PROMPT_PATH",
            DEFAULT_CRITIC_PROMPT_PATH,
            self._default_critic_prompt(),
        )
        self.deepseek_agent_prompt, self.deepseek_agent_prompt_meta = self._load_prompt(
            "FINAL_WRITER_AGENT_PROMPT_PATH",
            DEFAULT_DEEPSEEK_AGENT_PROMPT_PATH,
            self._default_deepseek_agent_prompt(),
        )
        self.tuner_response_schema, self.tuner_response_schema_meta = self._load_json_contract(
            "TUNER_RESPONSE_SCHEMA_PATH",
            DEFAULT_TUNER_RESPONSE_SCHEMA_PATH,
            self._default_tuner_response_schema(),
        )
        self.critic_response_schema, self.critic_response_schema_meta = self._load_json_contract(
            "CRITIC_RESPONSE_SCHEMA_PATH",
            DEFAULT_CRITIC_RESPONSE_SCHEMA_PATH,
            self._default_critic_response_schema(),
        )
        self.db_catalog_schema, self.db_catalog_schema_meta = self._load_json_contract(
            "DB_CATALOG_SCHEMA_PATH",
            DEFAULT_DB_CATALOG_SCHEMA_PATH,
            self._default_db_catalog_schema(),
        )
        self.db_query_context_schema, self.db_query_context_schema_meta = self._load_json_contract(
            "DB_QUERY_CONTEXT_SCHEMA_PATH",
            DEFAULT_DB_QUERY_CONTEXT_SCHEMA_PATH,
            self._default_db_query_context_schema(),
        )

        self.tmp_dir = self.workspace / "tmp"
        self.analysis_dir = self.workspace / "A"
        self.tuning_dir = self.workspace / "B"
        self.benchmark_dir = self.workspace / "benchmark"
        self.validation_dir = self.workspace / "validation"
        self.critique_dir = self.workspace / "critique"
        self.feedback_dir = self.workspace / "feedback"
        self.improved_dir = self.workspace / "improved"
        self.approved_dir = self.workspace / "approved"
        self.generated_dir = self.workspace / "generated"
        self.review_dir = self.workspace / "review"
        self.failed_dir = self.workspace / "failed"
        self.metadata_dir = self.workspace / "metadata"
        self.rag_dir = self.workspace / "rag"
        self.archive_dir = self.workspace / "archive"

        for directory in [
            self.tmp_dir,
            self.analysis_dir,
            self.tuning_dir,
            self.benchmark_dir,
            self.validation_dir,
            self.critique_dir,
            self.feedback_dir,
            self.improved_dir,
            self.approved_dir,
            self.generated_dir,
            self.review_dir,
            self.failed_dir,
            self.metadata_dir,
            self.rag_dir,
            self.archive_dir,
        ]:
            directory.mkdir(parents=True, exist_ok=True)
            os.chmod(directory, 0o700)

    def collect_sql(self) -> None:
        self._prepare_run_workspace()
        if self.mode == "oracle":
            self.jobs = self._collect_sql_from_oracle()
        elif self.mode == "files":
            self.jobs = self._collect_sql_from_files()
        else:
            raise ValueError(f"Unsupported mode: {self.mode}")

        if not self.jobs:
            raise RuntimeError(
                "No SQL statements were collected; refusing to report an empty run as SUCCESS."
            )

        self._log(f"collected {len(self.jobs)} SQL file(s) into {self.tmp_dir}")
        self._write_status()

    def _prepare_run_workspace(self) -> None:
        active_directories = [
            self.tmp_dir,
            self.analysis_dir,
            self.tuning_dir,
            self.benchmark_dir,
            self.validation_dir,
            self.critique_dir,
            self.feedback_dir,
            self.improved_dir,
            self.approved_dir,
            self.generated_dir,
            self.review_dir,
            self.failed_dir,
            self.metadata_dir,
            self.rag_dir,
        ]
        active_files = [self.workspace / "status.json", self.workspace / "summary.json"]
        has_previous_run = any(
            directory.exists() and any(directory.iterdir())
            for directory in active_directories
        ) or any(path.exists() for path in active_files)
        if not has_previous_run:
            return

        archive_name = time.strftime("run-%Y%m%d-%H%M%S") + f"-{time.time_ns() % 1_000_000:06d}"
        destination = self.archive_dir / archive_name
        destination.mkdir(parents=True, exist_ok=False)

        for directory in active_directories:
            if directory.exists() and any(directory.iterdir()):
                shutil.move(str(directory), str(destination / directory.name))
            directory.mkdir(parents=True, exist_ok=True)
        for path in active_files:
            if path.exists():
                shutil.move(str(path), str(destination / path.name))

        self._log(f"previous workspace archived into {destination}")

    def collect_metadata(self) -> None:
        query_metadata: list[dict[str, Any]] = []

        for job in self.jobs:
            sql = self._read_sql(job)
            job.tables = self.extract_tables(sql)
            query_metadata.append(
                {
                    "name": job.name,
                    "file": job.input_path.name,
                    "sql_id": job.sql_id,
                    "plan_hash_value": job.plan_hash_value,
                    "executions": job.executions,
                    "tables": job.tables,
                    "metrics": job.metrics,
                    "line_count": len(sql.splitlines()),
                    "char_count": len(sql),
                }
            )

        metadata_path = self.metadata_dir / "queries.json"
        metadata_path.write_text(
            json.dumps(query_metadata, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        self._log(f"metadata written: {metadata_path}")
        self._write_status()

    def build_rag(self) -> None:
        for job in self.jobs:
            db_context = self._load_db_context(job)
            rag_payload = {
                "name": job.name,
                "sql_id": job.sql_id or None,
                "plan_hash_value": job.plan_hash_value or None,
                "tables": job.tables,
                "metrics": job.metrics,
                "db_context": db_context,
            }
            context = [
                f"QUERY_NAME: {job.name}",
                f"SQL_ID: {job.sql_id or 'N/A'}",
                f"PLAN_HASH_VALUE: {job.plan_hash_value or 'N/A'}",
                "",
                "TABLES:",
                *(f"- {table}" for table in job.tables),
                "",
                "PERFORMANCE_BASELINE:",
                json.dumps(job.metrics, ensure_ascii=False, indent=2),
                "",
                "DB_CONTEXT:",
                json.dumps(db_context, ensure_ascii=False, indent=2),
            ]

            rag_path = self.rag_dir / f"{job.name}.txt"
            rag_path.write_text("\n".join(context), encoding="utf-8")
            rag_json_path = self.rag_dir / f"{job.name}.json"
            rag_json_path.write_text(
                self._json_dumps(rag_payload, pretty=True),
                encoding="utf-8",
            )

        self._log(f"rag context written for {len(self.jobs)} job(s)")
        self._write_status()

    def analyze_sql(self) -> None:
        for job in self.jobs:
            if job.status == QueryStatus.VERIFYING:
                continue
            job.status = QueryStatus.ANALYZING
            sql = self._read_sql(job)
            job.findings = self.find_static_findings(sql)
            critic_feedback = self._load_critic_feedback(job)
            critic_feedback_payload = self._load_critic_feedback_payload(job)
            analysis_payload = {
                "name": job.name,
                "sql_id": job.sql_id or None,
                "plan_hash_value": job.plan_hash_value or None,
                "executions": job.executions,
                "metrics": job.metrics,
                "tables": job.tables,
                "findings": job.findings,
                "target": {
                    "avg_elapsed_improvement_pct": self.improvement_threshold_pct,
                    "reduce": ["buffer_gets", "disk_reads"],
                    "preserve_semantics": True,
                },
                "critic_feedback": critic_feedback_payload,
            }

            lines = [
                f"# {job.name}",
                "",
                "## Query",
                f"- SQL_ID: {job.sql_id or 'N/A'}",
                f"- Plan Hash: {job.plan_hash_value or 'N/A'}",
                f"- Executions: {job.executions}",
                "",
                "## Baseline Metrics",
                *self._format_metrics(job.metrics),
                "",
                "## Tables",
                *(f"- {table}" for table in job.tables),
                "",
                "## Analysis",
            ]

            if job.findings:
                lines.extend(f"- {finding}" for finding in job.findings)
            else:
                lines.append("- 정적 분석 기준으로 즉시 보이는 위험은 없습니다.")

            if critic_feedback:
                lines.extend(
                    [
                        "",
                        "## Previous Critic Feedback",
                        critic_feedback.strip(),
                    ]
                )

            lines.extend(
                [
                    "",
                    "## Tuning Target",
                    f"- 평균 응답시간 {self.improvement_threshold_pct:.1f}% 이상 개선",
                    "- Buffer Gets / Disk Reads 감소",
                    "- 비즈니스 로직 동일성 유지",
                ]
            )

            job.analysis_path = self.analysis_dir / f"{job.name}.txt"
            job.analysis_path.write_text("\n".join(lines), encoding="utf-8")
            analysis_json_path = self.analysis_dir / f"{job.name}.json"
            analysis_json_path.write_text(
                self._json_dumps(analysis_payload, pretty=True),
                encoding="utf-8",
            )

        self._log(f"analysis written into {self.analysis_dir}")
        self._write_status()

    def tune_sql(self) -> None:
        self.tuning_round += 1
        writer_profile = self._current_writer_profile()
        round_dir = self.tuning_dir / "rounds" / f"round-{self.tuning_round}"
        round_dir.mkdir(parents=True, exist_ok=True)
        pending_jobs = [job for job in self.jobs if job.status != QueryStatus.VERIFYING]
        if pending_jobs and self._should_use_llm():
            self._ensure_model_endpoint(
                writer_profile["role"],
                writer_profile["model"],
                writer_profile["base_url"],
            )

        active_jobs = [job for job in self.jobs if job.status != QueryStatus.VERIFYING]
        total_jobs = len(active_jobs)
        for job_index, job in enumerate(active_jobs, start=1):
            job.status = QueryStatus.TUNING
            sql = self._read_sql(job)

            if self._should_use_llm():
                phase = (
                    "initial draft"
                    if self.tuning_round == 1
                    else "critic-feedback final rewrite"
                )
                writer_label = writer_profile["label"]
                started_at = time.monotonic()
                self._log(
                    f"{writer_label} {phase} [{job_index}/{total_jobs}] "
                    f"{job.name}: request started"
                )
                heartbeat_interval = max(0, int(writer_profile["heartbeat_sec"]))
                heartbeat_stop = threading.Event()
                heartbeat_thread: threading.Thread | None = None
                if heartbeat_interval > 0:
                    def heartbeat() -> None:
                        while not heartbeat_stop.wait(heartbeat_interval):
                            elapsed = time.monotonic() - started_at
                            self._log(
                                f"{writer_label} {phase} [{job_index}/{total_jobs}] "
                                f"{job.name}: "
                                f"still waiting ({elapsed:.0f}s)"
                            )

                    heartbeat_thread = threading.Thread(target=heartbeat, daemon=True)
                    heartbeat_thread.start()
                try:
                    tuning_result = self._tune_with_llm(job, sql)
                    job.error = None
                except Exception as exc:
                    job.error = f"tuner request failed: {exc}"
                    fallback_sql = sql
                    if self.tuning_round > 1 and job.tuned_path and job.tuned_path.is_file():
                        fallback_sql = job.tuned_path.read_text(encoding="utf-8").strip()
                    tuning_result = {
                        "sql": fallback_sql,
                        "why": ["previous_candidate_preserved_after_writer_failure"],
                        "risk": [job.error],
                        "check": ["retry_only_this_query_after_model_recovery"],
                    }
                    self._log(
                        f"{writer_label} {phase} [{job_index}/{total_jobs}] {job.name}: "
                        f"failed closed: {exc}"
                    )
                finally:
                    heartbeat_stop.set()
                    if heartbeat_thread is not None:
                        heartbeat_thread.join(timeout=1)
                self._log(
                    f"{writer_label} {phase} [{job_index}/{total_jobs}] {job.name}: "
                    f"completed in {time.monotonic() - started_at:.1f}s"
                )
            else:
                tuning_result = self._make_local_tuning_draft(job, sql)

            tuned_sql = str(tuning_result.get("sql") or "").strip()
            if not tuned_sql:
                raise RuntimeError(f"{job.name}: tuned SQL is empty")

            round_sql_path = round_dir / f"{job.name}-B.sql"
            round_sql_path.write_text(tuned_sql + "\n", encoding="utf-8")
            report_payload = {
                "name": job.name,
                "tuning_round": self.tuning_round,
                "phase": (
                    "initial" if self.tuning_round == 1 else "critic_feedback_retune"
                ),
                "sql_id": job.sql_id,
                "source": str(job.input_path),
                "tuned_sql": str(round_sql_path),
                "baseline_metrics": job.metrics,
                "findings": job.findings,
                "critic_feedback": self._load_critic_feedback_payload(job),
                "input_sql_source": (
                    "original" if self.tuning_round == 1 else "previous_tuning_round"
                ),
                "tuner": writer_profile["model"] if self._should_use_llm() else "local_draft",
                "writer_role": writer_profile["role"],
                "prompt": (
                    (
                        self.deepseek_agent_prompt_meta
                        if writer_profile["role"] == "writer:deepseek"
                        else self.tuner_prompt_meta
                    )
                    if self._should_use_llm()
                    else {"source": "not_used", "reason": "local_tuner"}
                ),
                "response_schema": (
                    self.tuner_response_schema_meta
                    if self._should_use_llm()
                    else {"source": "not_used", "reason": "local_tuner"}
                ),
                "llm_result": tuning_result,
            }
            round_report_path = round_dir / f"{job.name}-B.json"
            round_report_path.write_text(
                self._json_dumps(report_payload, pretty=True), encoding="utf-8"
            )

            job.tuned_path = self.tuning_dir / f"{job.name}-B.sql"
            job.tuned_path.write_text(tuned_sql + "\n", encoding="utf-8")
            report_path = self.tuning_dir / f"{job.name}-B.json"
            report_path.write_text(
                self._json_dumps(report_payload, pretty=True), encoding="utf-8"
            )
            self._write_status()

        self._log(
            f"tuning round {self.tuning_round} written into {round_dir}; "
            f"latest SQL into {self.tuning_dir}"
        )
        self._write_status()

    def benchmark(self) -> None:
        for job in self.jobs:
            if job.status == QueryStatus.VERIFYING:
                continue
            job.status = QueryStatus.BENCHMARKING
            existing_status = dict(job.benchmark)
            original_sql = self._read_sql(job)
            tuned_sql = job.tuned_path.read_text(encoding="utf-8") if job.tuned_path else ""

            benchmark = {
                "name": job.name,
                "sql_id": job.sql_id,
                "mode": "oracle_execute" if self.execute_benchmark else "baseline_only",
                "threshold_pct": self.improvement_threshold_pct,
                "original": job.metrics,
                "tuned": {},
                "improvement_pct": None,
                "improved": None,
                "performance_verified": self.execute_benchmark,
                "needs_review": True,
                "checked_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            }

            if self.execute_benchmark:
                benchmark.update(self._run_select_benchmark(job, original_sql, tuned_sql))
            else:
                benchmark["message"] = (
                    "실제 실행 벤치마크는 --execute-benchmark 옵션이 필요합니다. "
                    "현재 결과는 비평 승인/Oracle 검증 단계까지만 판정합니다."
                )

            for key in [
                "critic_approved",
                "critic_count",
                "critics",
                "critic_feedback_path",
                "oracle_validation_passed",
                "oracle_validation_path",
            ]:
                if key in existing_status:
                    benchmark[key] = existing_status[key]

            if (
                self.require_oracle_validation
                and benchmark.get("oracle_validation_passed") is not True
            ):
                benchmark["improved"] = False
                benchmark["needs_review"] = True
                benchmark["message"] = (
                    f"{benchmark.get('message', '')}; oracle validation missing or failed"
                ).strip("; ")

            if (
                self.require_critic_approval
                and benchmark.get("critic_approved") is not True
            ):
                benchmark["improved"] = False
                benchmark["needs_review"] = True
                benchmark["message"] = (
                    f"{benchmark.get('message', '')}; critic approval missing or rejected"
                ).strip("; ")

            if not self.execute_benchmark:
                gates_passed = (
                    (
                        not self.require_critic_approval
                        or benchmark.get("critic_approved") is True
                    )
                    and (
                        not self.require_oracle_validation
                        or benchmark.get("oracle_validation_passed") is True
                    )
                    and not job.error
                )
                benchmark["needs_review"] = not gates_passed
                benchmark["assessment_status"] = (
                    "approved_unbenchmarked" if gates_passed else "review_required"
                )
            else:
                benchmark["assessment_status"] = (
                    "benchmark_improved"
                    if benchmark.get("improved") is True
                    else "review_required"
                )

            job.benchmark = benchmark
            job.benchmark_path = self.benchmark_dir / f"{job.name}.json"
            job.benchmark_path.write_text(
                self._json_dumps(benchmark, pretty=True),
                encoding="utf-8",
            )

        self._log(f"benchmark reports written into {self.benchmark_dir}")
        self._write_status()

    def critique_tuned_sql(self) -> None:
        if not self.critics:
            self._log("critic review skipped: no critics configured")
            self._write_status()
            return

        self.critique_round += 1

        feedback_blocks_by_job: dict[str, list[dict[str, Any]]] = {
            job.name: [] for job in self.jobs
        }

        for job in self.jobs:
            if job.status == QueryStatus.VERIFYING:
                continue
            job.status = QueryStatus.CRITIQUING
            job_dir = self.critique_dir / job.name
            job_dir.mkdir(parents=True, exist_ok=True)

        for critic in self.critics:
            env_key = self._env_key(critic)
            model = (
                self._env(f"CRITIC_{env_key}_MODEL_NAME")
                or self._env("CRITIC_MODEL_NAME")
                or critic
            )
            base_url = (
                self._env(f"CRITIC_{env_key}_API_BASE_URL")
                or self._env("CRITIC_API_BASE_URL")
                or self._env("API_BASE_URL", "http://localhost:8080/v1")
            )
            self._ensure_model_endpoint(f"critic:{critic}", model, base_url)

            active_jobs = [
                job for job in self.jobs if job.status != QueryStatus.VERIFYING
            ]
            total_jobs = len(active_jobs)
            for job_index, job in enumerate(active_jobs, start=1):
                original_sql = self._read_sql(job)
                tuned_sql = job.tuned_path.read_text(encoding="utf-8") if job.tuned_path else ""
                job_dir = self.critique_dir / job.name
                started_at = time.monotonic()
                self._log(
                    f"critic {critic} [{job_index}/{total_jobs}] {job.name}: request started"
                )
                heartbeat_interval = max(0, int(self._env("CRITIC_HEARTBEAT_SEC", "15")))
                heartbeat_stop = threading.Event()
                heartbeat_thread: threading.Thread | None = None
                if heartbeat_interval > 0:
                    def heartbeat() -> None:
                        while not heartbeat_stop.wait(heartbeat_interval):
                            elapsed = time.monotonic() - started_at
                            self._log(
                                f"critic {critic} [{job_index}/{total_jobs}] {job.name}: "
                                f"still waiting ({elapsed:.0f}s)"
                            )

                    heartbeat_thread = threading.Thread(target=heartbeat, daemon=True)
                    heartbeat_thread.start()
                try:
                    report = self._call_critic_model(job, critic, original_sql, tuned_sql)
                except Exception as exc:
                    report = {
                        "critic": critic,
                        "approved": False,
                        "risk_level": "high",
                        "summary": f"critic call failed: {exc}",
                        "blocking_issues": [str(exc)],
                        "improvement_suggestions": [],
                        "semantic_risks": [],
                        "benchmark_notes": "",
                        "raw_text": "",
                    }
                finally:
                    heartbeat_stop.set()
                    if heartbeat_thread is not None:
                        heartbeat_thread.join(timeout=1)

                report = self._normalise_critic_report(critic, report)
                report["critique_round"] = self.critique_round
                report["tuning_round"] = self.tuning_round
                elapsed_seconds = time.monotonic() - started_at
                verdict = "approved" if report["approved"] else "rejected"
                self._log(
                    f"critic {critic} [{job_index}/{total_jobs}] {job.name}: "
                    f"{verdict} in {elapsed_seconds:.1f}s"
                )
                report["prompt"] = self.critic_prompt_meta
                report["response_schema"] = self.critic_response_schema_meta
                json_path = job_dir / f"{critic}.json"
                txt_path = job_dir / f"{critic}.txt"
                round_job_dir = job_dir / f"round-{self.critique_round}"
                round_job_dir.mkdir(parents=True, exist_ok=True)
                round_json_path = round_job_dir / f"{critic}.json"
                round_txt_path = round_job_dir / f"{critic}.txt"
                round_json_path.write_text(
                    json.dumps(report, ensure_ascii=False, indent=2),
                    encoding="utf-8",
                )
                round_txt_path.write_text(
                    self._format_critic_report_text(report), encoding="utf-8"
                )
                json_path.write_text(
                    json.dumps(report, ensure_ascii=False, indent=2),
                    encoding="utf-8",
                )
                txt_path.write_text(self._format_critic_report_text(report), encoding="utf-8")
                job.critiques[critic] = report
                job.critique_paths[critic] = str(json_path)
                feedback_blocks_by_job[job.name].append(self._format_feedback_block(report))
                self._write_status()

        for job in self.jobs:
            if job.status == QueryStatus.VERIFYING:
                continue
            feedback_reports = feedback_blocks_by_job[job.name]
            feedback_payload = {
                "name": job.name,
                "ok": all(bool(report.get("ok", False)) for report in feedback_reports),
                "critics": feedback_reports,
            }

            job.feedback_path = self.feedback_dir / f"{job.name}.json"
            job.feedback_path.write_text(
                self._json_dumps(feedback_payload),
                encoding="utf-8",
            )

            critic_approved = all(
                bool(report.get("approved", False)) for report in job.critiques.values()
            )
            job.benchmark["critic_approved"] = critic_approved
            job.benchmark["critic_count"] = len(self.critics)
            job.benchmark["critics"] = list(job.critiques.keys())
            job.benchmark["critic_feedback_path"] = str(job.feedback_path)

            if self.require_critic_approval and not critic_approved:
                previous_message = job.benchmark.get("message", "")
                suffix = "critic review rejected tuned SQL"
                job.benchmark["improved"] = False
                job.benchmark["needs_review"] = True
                job.benchmark["message"] = (
                    f"{previous_message}; {suffix}" if previous_message else suffix
                )

            if job.benchmark_path:
                job.benchmark_path.write_text(
                    json.dumps(job.benchmark, ensure_ascii=False, indent=2),
                    encoding="utf-8",
                )

        self._log(
            f"critic reports written into {self.critique_dir}; feedback into {self.feedback_dir}"
        )
        self._write_status()

    def prepare_critic_retune(self, round_number: int) -> None:
        for job in self.jobs:
            if job.status != QueryStatus.VERIFYING:
                job.retry_count += 1
                job.status = QueryStatus.RETRY
        self._log(
            f"Critic feedback saved ({', '.join(self.critics)}); "
            f"preparing DeepSeek 0731 feedback rewrite "
            f"[{round_number}/{self.critic_retune_rounds}]"
        )
        self._write_status()

    def should_retune_after_critique(self, completed_rounds: int) -> bool:
        return (
            bool(self.critics)
            and self._should_use_llm()
            and completed_rounds < self.critic_retune_rounds
        )

    def validate_oracle(self) -> None:
        if not self.oracle_validate:
            self._log("oracle validation skipped: enable --oracle-validate or --execute-benchmark")
            self._write_status()
            return

        for job in self.jobs:
            if job.status == QueryStatus.VERIFYING:
                continue
            job.status = QueryStatus.VALIDATING
            original_sql = self._read_sql(job).strip()
            tuned_sql = (
                job.tuned_path.read_text(encoding="utf-8").strip()
                if job.tuned_path
                else ""
            )
            validation = self._validate_sql_pair_with_oracle(job, original_sql, tuned_sql)
            job.validation = validation
            job.validation_path = self.validation_dir / f"{job.name}.json"
            job.validation_path.write_text(
                self._json_dumps(validation, pretty=True),
                encoding="utf-8",
            )

            job.benchmark["oracle_validation_passed"] = validation["passed"]
            job.benchmark["oracle_validation_path"] = str(job.validation_path)
            if not validation["passed"]:
                job.benchmark["improved"] = False
                job.benchmark["needs_review"] = True
                job.benchmark["message"] = validation.get("message", "oracle validation failed")
                self._merge_feedback_payload(
                    job,
                    {
                        "oracle_validation": {
                            "ok": False,
                            "stage": validation.get("failed_stage"),
                            "message": validation.get("message"),
                            "errors": validation.get("errors", []),
                            "rules": validation.get("rules", []),
                        }
                    },
                )

        self._log(f"oracle validation reports written into {self.validation_dir}")
        self._write_status()

    def is_improved(self) -> bool:
        for job in self.jobs:
            job.status = QueryStatus.VERIFYING

        self._write_status()
        return all(self._job_passed_final_verification(job) for job in self.jobs)

    def move_success(self) -> None:
        destination = self._success_output_dir()
        for job in self.jobs:
            if job.tuned_path and job.tuned_path.exists():
                shutil.copy2(job.tuned_path, destination / job.tuned_path.name)
            job.status = QueryStatus.SUCCESS

        if self.execute_benchmark:
            result = "SUCCESS"
        elif self.oracle_validate:
            result = "ORACLE_VALIDATED_UNBENCHMARKED"
        elif self.require_critic_approval:
            result = "CRITIC_APPROVED_UNBENCHMARKED"
        else:
            result = "GENERATED_UNVALIDATED"
        self._write_summary(result)
        self._write_status()
        self._log(f"success: {len(self.jobs)} job(s) moved to {destination}")

    def move_failed(self) -> None:
        success_count = 0
        for job in self.jobs:
            passed = self._job_passed_final_verification(job)
            if job.tuned_path and job.tuned_path.exists():
                destination = self._success_output_dir() if passed else self.failed_dir
                shutil.copy2(job.tuned_path, destination / job.tuned_path.name)
            if passed:
                job.status = QueryStatus.SUCCESS
                success_count += 1
            else:
                job.status = QueryStatus.FAILED

        result = "PARTIAL" if success_count else "FAILED"
        self._write_summary(result)
        self._write_status()
        self._log(
            f"{result.lower()}: {success_count} accepted, "
            f"{len(self.jobs) - success_count} failed"
        )

    def _success_output_dir(self) -> Path:
        if self.execute_benchmark:
            return self.improved_dir
        if self.oracle_validate or self.require_critic_approval:
            return self.approved_dir
        return self.generated_dir

    def notify_user(self) -> None:
        review_path = self.review_dir / "needs_review.txt"
        lines = [
            "자동 개선 검증을 통과하지 못했습니다.",
            "benchmark/*.json 파일을 확인한 뒤 재분석 또는 수동 승인을 진행하세요.",
            "",
            "Review targets:",
        ]

        for job in self.jobs:
            if not self._job_passed_final_verification(job):
                feedback = f" feedback={job.feedback_path}" if job.feedback_path else ""
                lines.append(
                    f"- {job.name}: {job.benchmark.get('message', 'needs review')}{feedback}"
                )

        review_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        self._log(f"user review note written: {review_path}")

    def wait_user(self) -> None:
        self._log("non-interactive run: review note created, then marking as failed")

    def retry_jobs(self) -> None:
        for job in self.jobs:
            if not self._job_passed_final_verification(job):
                job.retry_count += 1
                job.status = QueryStatus.RETRY

        self._write_status()

    def print_summary(self) -> None:
        summary_path = self.workspace / "summary.json"
        if summary_path.exists():
            print(summary_path.read_text(encoding="utf-8"))

    def _collect_sql_from_oracle(self) -> list[QueryJob]:
        rows = self._fetch_oracle_sql_rows()
        jobs: list[QueryJob] = []

        for idx, row in enumerate(rows, 1):
            sql_id = str(row.get("sql_id") or "nosqlid")
            plan_hash = int(row.get("plan_hash_value") or 0)
            name = f"{idx:04d}_{sql_id}_{plan_hash}"
            input_path = self.tmp_dir / f"{name}.sql"
            input_path.write_text(
                str(row.get("sql_text") or "").strip() + "\n", encoding="utf-8"
            )

            metrics = self._metrics_from_oracle_row(row)
            jobs.append(
                QueryJob(
                    name=name,
                    source_path=input_path,
                    input_path=input_path,
                    sql_id=sql_id,
                    child_number=int(row.get("child_number") or 0),
                    plan_hash_value=plan_hash,
                    parsing_schema_name=str(
                        row.get("parsing_schema_name") or ""
                    ).strip(),
                    executions=int(row.get("executions") or 0),
                    metrics=metrics,
                )
            )

        return jobs

    def _collect_sql_from_files(self) -> list[QueryJob]:
        jobs: list[QueryJob] = []
        sql_files: list[Path] = []
        seen_files: set[Path] = set()

        for source_dir in self.source_dirs:
            if not source_dir.exists():
                self._log(f"source directory not found: {source_dir}")
                continue
            candidates = [source_dir] if source_dir.is_file() else source_dir.rglob("*.sql")
            for sql_file in candidates:
                if not sql_file.is_file() or sql_file.suffix.lower() != ".sql":
                    continue
                resolved = sql_file.resolve()
                if resolved in seen_files:
                    continue
                seen_files.add(resolved)
                sql_files.append(resolved)

        sql_files.sort(key=lambda path: str(path).casefold())
        for idx, sql_file in enumerate(sql_files, 1):
            name = f"{idx:04d}_{sql_file.stem}"
            input_path = self.tmp_dir / f"{name}.sql"
            shutil.copy2(sql_file, input_path)
            jobs.append(
                QueryJob(
                    name=name,
                    source_path=sql_file,
                    input_path=input_path,
                    executions=0,
                    metrics={
                        "source": "file_mode",
                        "source_directory": str(sql_file.parent),
                        "avg_elapsed_ms": None,
                        "avg_buffer_gets": None,
                        "avg_disk_reads": None,
                    },
                )
            )

        return jobs

    def _fetch_oracle_sql_rows(self) -> list[dict[str, Any]]:
        try:
            import oracledb
        except ImportError as exc:
            raise RuntimeError(
                "python-oracledb가 설치되어 있지 않습니다. "
                f"`{sys.executable} -m pip install -r "
                f"{SCRIPT_DIR / 'requirements.txt'}` 실행 후 다시 시도하세요."
            ) from exc

        user = self._env("ORACLE_USER")
        password = self._env("ORACLE_PASSWORD")
        dsn = self._env("ORACLE_DSN")

        if not user or not password or not dsn:
            raise RuntimeError(
                "Oracle 접속정보가 필요합니다: ORACLE_USER, ORACLE_PASSWORD, ORACLE_DSN"
            )

        sql = """
SELECT *
FROM (
    SELECT
        sql_id,
        child_number,
        plan_hash_value,
        executions,
        elapsed_time,
        cpu_time,
        buffer_gets,
        disk_reads,
        rows_processed,
        fetches,
        parse_calls,
        module,
        parsing_schema_name,
        last_active_time,
        sql_fulltext AS sql_text
    FROM v$sql
    WHERE last_active_time >= SYSDATE - (:collect_hours / 24)
      AND executions >= :min_executions
      AND sql_fulltext IS NOT NULL
      AND parsing_schema_name NOT IN ('SYS', 'SYSTEM')
      AND command_type = 3
    ORDER BY elapsed_time DESC, buffer_gets DESC, executions DESC
)
WHERE ROWNUM <= :query_limit
"""

        with oracledb.connect(user=user, password=password, dsn=dsn) as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    sql,
                    collect_hours=self.collect_hours,
                    min_executions=self.min_executions,
                    query_limit=self.query_limit,
                )
                columns = [col[0].lower() for col in cursor.description]
                rows: list[dict[str, Any]] = []
                for row in cursor.fetchall():
                    item = dict(zip(columns, row))
                    sql_text = item.get("sql_text")
                    if hasattr(sql_text, "read"):
                        sql_text = sql_text.read()
                    item["sql_text"] = str(sql_text or "")
                    rows.append(item)
                return rows

    def _metrics_from_oracle_row(self, row: dict[str, Any]) -> dict[str, Any]:
        executions = max(int(row.get("executions") or 0), 1)

        def per_exec(name: str, scale: float = 1.0) -> float:
            return round((float(row.get(name) or 0) / executions) / scale, 4)

        return {
            "source": "v$sql",
            "executions": int(row.get("executions") or 0),
            "avg_elapsed_ms": per_exec("elapsed_time", 1000.0),
            "avg_cpu_ms": per_exec("cpu_time", 1000.0),
            "avg_buffer_gets": per_exec("buffer_gets"),
            "avg_disk_reads": per_exec("disk_reads"),
            "avg_rows_processed": per_exec("rows_processed"),
            "total_elapsed_ms": round(float(row.get("elapsed_time") or 0) / 1000.0, 4),
            "total_cpu_ms": round(float(row.get("cpu_time") or 0) / 1000.0, 4),
            "buffer_gets": int(row.get("buffer_gets") or 0),
            "disk_reads": int(row.get("disk_reads") or 0),
            "rows_processed": int(row.get("rows_processed") or 0),
            "fetches": int(row.get("fetches") or 0),
            "parse_calls": int(row.get("parse_calls") or 0),
            "module": str(row.get("module") or ""),
            "parsing_schema_name": str(row.get("parsing_schema_name") or ""),
            "last_active_time": str(row.get("last_active_time") or ""),
        }

    def _should_use_llm(self) -> bool:
        if self.tuner == "local":
            return False
        if self.tuner == "llm":
            return True
        return bool(self._env("API_BASE_URL"))

    def _active_tuner_name(self) -> str:
        if not self._should_use_llm():
            return "local_draft"
        return self._current_writer_profile()["model"]

    def _current_writer_profile(self) -> dict[str, str]:
        use_final_writer = self.tuning_round > 1 and self._env_bool(
            "FINAL_WRITER_ENABLED", True
        )
        if use_final_writer:
            return {
                "role": "writer:deepseek",
                "label": self._env("FINAL_WRITER_LABEL", "DeepSeek 0731"),
                "model": self._env(
                    "FINAL_WRITER_MODEL_NAME", "deepseek-v4-flash"
                ),
                "base_url": self._env(
                    "FINAL_WRITER_API_BASE_URL",
                    self._env("API_BASE_URL", "http://localhost:8080/v1"),
                ),
                "api_key": self._env(
                    "FINAL_WRITER_API_KEY", self._env("API_KEY", "sk-local")
                ),
                "temperature": self._env("FINAL_WRITER_TEMPERATURE", "0"),
                "top_p": self._env("FINAL_WRITER_TOP_P", "1.0"),
                "top_k": self._env("FINAL_WRITER_TOP_K", "0"),
                "min_p": self._env("FINAL_WRITER_MIN_P", "0.0"),
                "presence_penalty": self._env(
                    "FINAL_WRITER_PRESENCE_PENALTY", "0.0"
                ),
                "frequency_penalty": self._env(
                    "FINAL_WRITER_FREQUENCY_PENALTY", "0.0"
                ),
                "repetition_penalty": self._env(
                    "FINAL_WRITER_REPETITION_PENALTY", "1.0"
                ),
                "seed": self._env("FINAL_WRITER_SEED", "42"),
                "max_tokens": self._env("FINAL_WRITER_MAX_TOKENS", "16384"),
                "context_size": self._env("FINAL_WRITER_CONTEXT_SIZE", "32768"),
                "context_safety_tokens": self._env(
                    "FINAL_WRITER_CONTEXT_SAFETY_TOKENS", "4096"
                ),
                "min_output_tokens": self._env(
                    "FINAL_WRITER_MIN_OUTPUT_TOKENS", "2048"
                ),
                "request_style": self._env(
                    "FINAL_WRITER_REQUEST_STYLE", "ds4"
                ),
                "thinking_mode": self._env(
                    "FINAL_WRITER_THINKING_MODE", "thinking"
                ),
                "reasoning_effort": self._env(
                    "FINAL_WRITER_REASONING_EFFORT", "max"
                ),
                "agent_mode": self._env("FINAL_WRITER_AGENT_MODE", "minimal"),
                "reasoning_format": "",
                "thinking": "",
                "cache_prompt": self._env("FINAL_WRITER_CACHE_PROMPT", "1"),
                "structured_output": self._env(
                    "FINAL_WRITER_STRUCTURED_OUTPUT", "0"
                ),
                "timeout_sec": self._env("FINAL_WRITER_TIMEOUT_SEC", "10800"),
                "api_attempts": self._env("FINAL_WRITER_API_ATTEMPTS", "2"),
                "heartbeat_sec": self._env("FINAL_WRITER_HEARTBEAT_SEC", "15"),
            }

        return {
            "role": "tuner",
            "label": self._env("TUNER_LABEL", "Qwen"),
            "model": self._env("MODEL_NAME", "qwen-sql-tuner"),
            "base_url": self._env("API_BASE_URL", "http://localhost:8080/v1"),
            "api_key": self._env("API_KEY", "sk-local"),
            "temperature": self._env("TUNER_TEMPERATURE", "0.6"),
            "top_p": self._env("TUNER_TOP_P", "0.95"),
            "top_k": self._env("TUNER_TOP_K", "20"),
            "min_p": self._env("TUNER_MIN_P", "0.0"),
            "presence_penalty": self._env("TUNER_PRESENCE_PENALTY", "0.0"),
            "frequency_penalty": self._env("TUNER_FREQUENCY_PENALTY", "0.0"),
            "repetition_penalty": self._env("TUNER_REPETITION_PENALTY", "1.0"),
            "seed": self._env("TUNER_SEED", "42"),
            "max_tokens": self._env("TUNER_MAX_TOKENS", "0"),
            "context_size": self._env(
                "TUNER_CONTEXT_SIZE", self._env("QWEN_CTX_SIZE", "131072")
            ),
            "context_safety_tokens": self._env(
                "TUNER_CONTEXT_SAFETY_TOKENS", "4096"
            ),
            "min_output_tokens": self._env("TUNER_MIN_OUTPUT_TOKENS", "2048"),
            "request_style": "qwen",
            "thinking_mode": "",
            "reasoning_effort": "",
            "agent_mode": "",
            "reasoning_format": self._env("TUNER_REASONING_FORMAT", "deepseek"),
            "thinking": self._env("TUNER_THINKING", "1"),
            "cache_prompt": self._env("TUNER_CACHE_PROMPT", "1"),
            "structured_output": self._env("TUNER_STRUCTURED_OUTPUT", "1"),
            "timeout_sec": self._env("TUNER_TIMEOUT_SEC", "1800"),
            "api_attempts": self._env("TUNER_API_ATTEMPTS", "2"),
            "heartbeat_sec": self._env("TUNER_HEARTBEAT_SEC", "15"),
        }

    def _refresh_tuner_prompt(self) -> None:
        self.tuner_prompt, self.tuner_prompt_meta = self._load_prompt(
            "TUNER_PROMPT_PATH",
            DEFAULT_TUNER_PROMPT_PATH,
            self._default_tuner_prompt(),
        )
        self.deepseek_agent_prompt, self.deepseek_agent_prompt_meta = self._load_prompt(
            "FINAL_WRITER_AGENT_PROMPT_PATH",
            DEFAULT_DEEPSEEK_AGENT_PROMPT_PATH,
            self._default_deepseek_agent_prompt(),
        )
        self.tuner_response_schema, self.tuner_response_schema_meta = self._load_json_contract(
            "TUNER_RESPONSE_SCHEMA_PATH",
            DEFAULT_TUNER_RESPONSE_SCHEMA_PATH,
            self._default_tuner_response_schema(),
        )

    def _refresh_critic_prompt(self) -> None:
        self.critic_prompt, self.critic_prompt_meta = self._load_prompt(
            "CRITIC_PROMPT_PATH",
            DEFAULT_CRITIC_PROMPT_PATH,
            self._default_critic_prompt(),
        )
        self.critic_response_schema, self.critic_response_schema_meta = self._load_json_contract(
            "CRITIC_RESPONSE_SCHEMA_PATH",
            DEFAULT_CRITIC_RESPONSE_SCHEMA_PATH,
            self._default_critic_response_schema(),
        )

    def _load_prompt(
        self,
        env_name: str,
        default_path: Path,
        fallback: str,
    ) -> tuple[str, dict[str, Any]]:
        path = self._resolve_prompt_path(self._env(env_name), default_path)
        text = fallback.strip()
        source = "fallback"

        if path.exists():
            file_text = path.read_text(encoding="utf-8").strip()
            if file_text:
                text = file_text
                source = "file"

        return text, {
            "env": env_name,
            "path": str(path),
            "source": source,
            "sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
            "chars": len(text),
        }

    def _load_json_contract(
        self,
        env_name: str,
        default_path: Path,
        fallback: dict[str, Any],
    ) -> tuple[dict[str, Any], dict[str, Any]]:
        path = self._resolve_prompt_path(self._env(env_name), default_path)
        schema = fallback
        source = "fallback"

        if path.exists():
            try:
                loaded = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError as exc:
                raise RuntimeError(f"Invalid JSON contract {path}: {exc}") from exc
            if not isinstance(loaded, dict):
                raise RuntimeError(f"JSON contract must be an object: {path}")
            schema = loaded
            source = "file"

        encoded = self._json_dumps(schema)
        return schema, {
            "env": env_name,
            "path": str(path),
            "source": source,
            "sha256": hashlib.sha256(encoded.encode("utf-8")).hexdigest(),
        }

    def _resolve_prompt_path(self, configured: str, default_path: Path) -> Path:
        if not configured:
            return default_path

        path = Path(configured).expanduser()
        if path.is_absolute():
            return path

        candidates = [
            Path.cwd() / path,
            SCRIPT_DIR / path,
            REPO_ROOT / path,
            self.workspace.parent / path,
            self.workspace.parent.parent / path,
        ]
        for candidate in candidates:
            if candidate.exists():
                return candidate.resolve()
        return (SCRIPT_DIR / path).resolve()

    def _render_tuner_prompt(self, job: QueryJob, analysis_payload: Any) -> str:
        # LEGACY (disabled): custom prompts once embedded a rendered `{db_schema}`
        # placeholder in the system prompt. Dynamic DB data now belongs only in the
        # per-request user payload under `db_context`.
        # if "{db_schema}" in self.tuner_prompt:
        #     return self.tuner_prompt.replace(
        #         "{db_schema}",
        #         self._prompt_schema_context(job, analysis_payload),
        #     )
        return self.tuner_prompt

    # LEGACY (disabled): helper for the old `{db_schema}` system-prompt injection.
    # def _prompt_schema_context(self, job: QueryJob, analysis_payload: Any) -> str:
    #     context = {
    #         "query_name": job.name,
    #         "sql_id": job.sql_id or None,
    #         "plan_hash_value": job.plan_hash_value or None,
    #         "tables": job.tables,
    #         "baseline_metrics": job.metrics,
    #         "analysis": analysis_payload if isinstance(analysis_payload, dict) else {},
    #         "rag_context_path": str(self.rag_dir / f"{job.name}.json"),
    #         "db_context": self._load_db_context(job),
    #     }
    #     return self._json_dumps(context)

    @staticmethod
    def _default_tuner_prompt() -> str:
        return (
            "You are a senior Oracle 19c SQL tuning engineer. "
            "Preserve business logic exactly. Return strict compact JSON only with schema "
            '{"sql":"...","why":["..."],"risk":["..."],"check":["..."]}. '
            "The sql field must contain executable Oracle SQL only."
        )

    @staticmethod
    def _default_deepseek_agent_prompt() -> str:
        return (
            "Operate as a minimal single-turn code agent for this Oracle SQL rewrite. "
            "Use maximum private reasoning effort before answering. Thoroughly decompose "
            "the supplied evidence, test assumptions and edge cases, and reject unsafe "
            "alternatives. Do not request tools or additional turns. Return only the "
            "required compact JSON and never expose private reasoning."
        )

    @staticmethod
    def _default_critic_prompt() -> str:
        return (
            "You are an independent Oracle 19c SQL tuning critic. "
            "Review semantic drift, Oracle syntax risk, cardinality risk, and benchmark risk. "
            "Return strict compact JSON only with schema "
            '{"ok":true,"risk":"low|medium|high","sum":"...",'
            '"block":["..."],"fix":["..."],"sem":["..."],"bench":"..."}.'
        )

    @staticmethod
    def _default_tuner_response_schema() -> dict[str, Any]:
        string_array = {"type": "array", "items": {"type": "string"}}
        return {
            "type": "object",
            "properties": {
                "sql": {"type": "string", "minLength": 1},
                "why": string_array,
                "risk": string_array,
                "check": string_array,
            },
            "required": ["sql", "why", "risk", "check"],
            "additionalProperties": False,
        }

    @staticmethod
    def _default_critic_response_schema() -> dict[str, Any]:
        string_array = {"type": "array", "items": {"type": "string"}}
        return {
            "type": "object",
            "properties": {
                "ok": {"type": "boolean"},
                "risk": {"type": "string", "enum": ["low", "medium", "high"]},
                "sum": {"type": "string", "minLength": 1},
                "block": string_array,
                "fix": string_array,
                "sem": string_array,
                "bench": {"type": "string"},
            },
            "required": ["ok", "risk", "sum", "block", "fix", "sem", "bench"],
            "additionalProperties": False,
        }

    @staticmethod
    def _default_db_catalog_schema() -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "metadata_version": {"type": "integer"},
                "captured_at": {"type": "string"},
                "database": {"type": "object"},
                "objects": {"type": "array", "items": {"type": "object"}},
            },
            "required": ["metadata_version", "captured_at", "database", "objects"],
            "additionalProperties": False,
        }

    @staticmethod
    def _default_db_query_context_schema() -> dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "captured_at": {"type": "string"},
                "binds": {"type": "array"},
                "execution_plan": {"type": "object"},
                "runtime_metrics": {"type": "object"},
            },
            "required": ["captured_at", "binds", "execution_plan", "runtime_metrics"],
        }

    def _load_db_context(self, job: QueryJob) -> dict[str, Any]:
        configured_catalog = self._env("DB_CATALOG_PATH")
        catalog_path = self._resolve_prompt_path(
            configured_catalog,
            DEFAULT_DB_CATALOG_PATH,
        )
        catalog: dict[str, Any] = {}
        selected_objects: list[dict[str, Any]] = []
        unresolved_objects = list(job.tables)
        catalog_meta: dict[str, Any] = {"loaded": False}

        if catalog_path.exists():
            catalog = self._read_required_json_object(catalog_path)
            contract_errors = self._validate_json_contract(catalog, self.db_catalog_schema)
            if contract_errors:
                raise RuntimeError(
                    f"DB catalog contract failed for {catalog_path}: "
                    + "; ".join(contract_errors)
                )
            selected_objects, unresolved_objects = self._select_relevant_db_objects(
                catalog.get("objects", []),
                job.tables,
            )
            catalog_text = self._json_dumps(catalog)
            catalog_meta = {
                "loaded": True,
                "captured_at": catalog.get("captured_at"),
                "sha256": hashlib.sha256(catalog_text.encode("utf-8")).hexdigest(),
                "selected_object_count": len(selected_objects),
            }
        elif configured_catalog:
            raise RuntimeError(f"Configured DB catalog does not exist: {catalog_path}")

        configured_query_dir = self._env("DB_QUERY_CONTEXT_DIR")
        query_dir = self._resolve_prompt_path(
            configured_query_dir,
            DEFAULT_DB_QUERY_CONTEXT_DIR,
        )
        query_context: dict[str, Any] = {}
        query_meta: dict[str, Any] = {"loaded": False}
        if query_dir.exists():
            candidate_names = [job.name]
            if job.sql_id:
                candidate_names.insert(0, job.sql_id)
            for candidate_name in candidate_names:
                safe_name = re.sub(r"[^A-Za-z0-9_.-]+", "_", candidate_name)
                candidate = query_dir / f"{safe_name}.json"
                if not candidate.exists():
                    continue
                query_context = self._read_required_json_object(candidate)
                contract_errors = self._validate_json_contract(
                    query_context,
                    self.db_query_context_schema,
                )
                if contract_errors:
                    raise RuntimeError(
                        f"DB query context contract failed for {candidate}: "
                        + "; ".join(contract_errors)
                    )
                query_text = self._json_dumps(query_context)
                query_meta = {
                    "loaded": True,
                    "key": safe_name,
                    "captured_at": query_context.get("captured_at"),
                    "sha256": hashlib.sha256(query_text.encode("utf-8")).hexdigest(),
                }
                break
        elif configured_query_dir:
            raise RuntimeError(f"Configured DB query context directory does not exist: {query_dir}")

        return {
            "catalog": catalog_meta,
            "database": catalog.get("database", {}),
            "objects": selected_objects,
            "unresolved_objects": unresolved_objects,
            "query": query_context,
            "query_context": query_meta,
        }

    @staticmethod
    def _read_required_json_object(path: Path) -> dict[str, Any]:
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise RuntimeError(f"Invalid JSON file {path}: {exc}") from exc
        if not isinstance(payload, dict):
            raise RuntimeError(f"JSON file must contain an object: {path}")
        return payload

    @staticmethod
    def _select_relevant_db_objects(
        objects: Any,
        referenced_tables: list[str],
    ) -> tuple[list[dict[str, Any]], list[str]]:
        if not isinstance(objects, list):
            return [], list(referenced_tables)

        valid_objects = [item for item in objects if isinstance(item, dict)]
        lookup: dict[str, list[dict[str, Any]]] = {}
        for item in valid_objects:
            name = str(item.get("name") or "").strip().upper()
            owner = str(item.get("owner") or "").strip().upper()
            if not name:
                continue
            lookup.setdefault(name, []).append(item)
            if owner:
                lookup.setdefault(f"{owner}.{name}", []).append(item)

        selected: list[dict[str, Any]] = []
        selected_ids: set[int] = set()
        queue: list[dict[str, Any]] = []
        unresolved: list[str] = []

        for table in referenced_tables:
            key = str(table).strip('"').upper()
            matches = lookup.get(key) or lookup.get(key.split(".")[-1]) or []
            if not matches:
                unresolved.append(table)
            queue.extend(matches)

        while queue:
            item = queue.pop(0)
            marker = id(item)
            if marker in selected_ids:
                continue
            selected_ids.add(marker)
            selected.append(item)
            dependencies = item.get("dependencies", [])
            if not isinstance(dependencies, list):
                continue
            for dependency in dependencies:
                key = str(dependency).strip('"').upper()
                queue.extend(lookup.get(key) or lookup.get(key.split(".")[-1]) or [])

        return selected, unresolved

    @classmethod
    def _validate_json_contract(
        cls,
        value: Any,
        schema: dict[str, Any],
        path: str = "$",
    ) -> list[str]:
        errors: list[str] = []
        expected_type = schema.get("type")
        if expected_type is not None and not cls._json_type_matches(value, expected_type):
            return [f"{path}: expected {expected_type}"]

        if "enum" in schema and value not in schema["enum"]:
            errors.append(f"{path}: value is not in enum")

        if isinstance(value, dict):
            properties = schema.get("properties", {})
            required = schema.get("required", [])
            for key in required:
                if key not in value:
                    errors.append(f"{path}: missing required property {key}")
            if schema.get("additionalProperties") is False:
                for key in value:
                    if key not in properties:
                        errors.append(f"{path}: unexpected property {key}")
            for key, child_schema in properties.items():
                if key in value and isinstance(child_schema, dict):
                    errors.extend(
                        cls._validate_json_contract(value[key], child_schema, f"{path}.{key}")
                    )

        if isinstance(value, list):
            min_items = schema.get("minItems")
            if isinstance(min_items, int) and len(value) < min_items:
                errors.append(f"{path}: fewer than {min_items} items")
            max_items = schema.get("maxItems")
            if isinstance(max_items, int) and len(value) > max_items:
                errors.append(f"{path}: more than {max_items} items")
            item_schema = schema.get("items")
            if isinstance(item_schema, dict):
                for index, item in enumerate(value):
                    errors.extend(
                        cls._validate_json_contract(item, item_schema, f"{path}[{index}]")
                    )

        if isinstance(value, str):
            min_length = schema.get("minLength")
            if isinstance(min_length, int) and len(value) < min_length:
                errors.append(f"{path}: shorter than {min_length} characters")
            max_length = schema.get("maxLength")
            if isinstance(max_length, int) and len(value) > max_length:
                errors.append(f"{path}: longer than {max_length} characters")

        return errors

    @staticmethod
    def _json_type_matches(value: Any, expected_type: Any) -> bool:
        if isinstance(expected_type, list):
            return any(PipelineManager._json_type_matches(value, item) for item in expected_type)
        checks = {
            "object": lambda: isinstance(value, dict),
            "array": lambda: isinstance(value, list),
            "string": lambda: isinstance(value, str),
            "boolean": lambda: isinstance(value, bool),
            "integer": lambda: isinstance(value, int) and not isinstance(value, bool),
            "number": lambda: isinstance(value, (int, float)) and not isinstance(value, bool),
            "null": lambda: value is None,
        }
        check = checks.get(str(expected_type))
        return True if check is None else check()

    @staticmethod
    def _json_schema_response_format(name: str, schema: dict[str, Any]) -> dict[str, Any]:
        return {
            "type": "json_schema",
            "json_schema": {
                "name": name,
                "schema": schema,
            },
        }

    @staticmethod
    def _generation_request_config(payload: dict[str, Any]) -> dict[str, Any]:
        keys = (
            "model",
            "temperature",
            "top_p",
            "top_k",
            "min_p",
            "presence_penalty",
            "frequency_penalty",
            "repeat_penalty",
            "seed",
            "max_tokens",
            "thinking",
            "reasoning_effort",
            "reasoning_format",
            "cache_prompt",
            "chat_template_kwargs",
        )
        return {key: payload[key] for key in keys if key in payload}

    def _tune_with_llm(self, job: QueryJob, sql: str) -> dict[str, Any]:
        self._refresh_tuner_prompt()
        writer_profile = self._current_writer_profile()
        base_url = writer_profile["base_url"].rstrip("/")
        api_key = writer_profile["api_key"]
        model = writer_profile["model"]
        analysis_payload = self._load_json_file(self.analysis_dir / f"{job.name}.json")
        if not analysis_payload and job.analysis_path:
            analysis_payload = {"text": job.analysis_path.read_text(encoding="utf-8")}
        critic_feedback = self._load_critic_feedback_payload(job)
        previous_tuned_sql = ""
        if critic_feedback and job.tuned_path and job.tuned_path.is_file():
            previous_tuned_sql = job.tuned_path.read_text(encoding="utf-8").strip()
        tuning_input = {
            "analysis": analysis_payload,
            "baseline": job.metrics,
            "sql": previous_tuned_sql or sql,
            "db_context": self._load_db_context(job),
            "critic_feedback": critic_feedback,
        }
        if previous_tuned_sql:
            # In a feedback round the current candidate and the original are both
            # useful, but the candidate must not be duplicated under two keys.
            tuning_input["original_sql"] = sql
        fallback_sql = previous_tuned_sql or sql

        system_prompt = self._render_tuner_prompt(job, analysis_payload)
        if (
            writer_profile["role"] == "writer:deepseek"
            and writer_profile["agent_mode"].strip().lower() == "minimal"
        ):
            system_prompt = f"{self.deepseek_agent_prompt}\n\n{system_prompt}"

        payload = {
            "model": model,
            "temperature": float(writer_profile["temperature"]),
            "top_p": float(writer_profile["top_p"]),
            "top_k": int(writer_profile["top_k"]),
            "min_p": float(writer_profile["min_p"]),
            "presence_penalty": float(writer_profile["presence_penalty"]),
            "frequency_penalty": float(writer_profile["frequency_penalty"]),
            "repeat_penalty": float(writer_profile["repetition_penalty"]),
            "seed": int(writer_profile["seed"]),
            "messages": [
                {
                    "role": "system",
                    "content": system_prompt,
                },
                {
                    "role": "user",
                    "content": self._json_dumps(tuning_input),
                },
            ],
        }
        tuner_max_tokens = int(writer_profile["max_tokens"])
        if tuner_max_tokens > 0:
            context_size = max(
                1,
                int(writer_profile["context_size"]),
            )
            safety_tokens = max(
                0, int(writer_profile["context_safety_tokens"])
            )
            estimated_input_tokens = self._estimate_tokens(
                self._json_dumps(payload["messages"])
            )
            available_output_tokens = context_size - estimated_input_tokens - safety_tokens
            minimum_output_tokens = max(
                256, int(writer_profile["min_output_tokens"])
            )
            if available_output_tokens < minimum_output_tokens:
                raise RuntimeError(
                    "tuner input exceeds the configured context budget: "
                    f"estimated_input={estimated_input_tokens}, context={context_size}, "
                    f"safety={safety_tokens}"
                )
            payload["max_tokens"] = min(tuner_max_tokens, available_output_tokens)
            context_budget = {
                "context_size": context_size,
                "estimated_input_tokens": estimated_input_tokens,
                "safety_tokens": safety_tokens,
                "requested_output_tokens": tuner_max_tokens,
                "effective_output_tokens": payload["max_tokens"],
                "requested_reasoning_effort": writer_profile["reasoning_effort"],
                "effective_reasoning_effort": (
                    "high"
                    if writer_profile["request_style"].strip().lower() == "ds4"
                    and writer_profile["reasoning_effort"].strip().lower() == "max"
                    and context_size < 393216
                    else writer_profile["reasoning_effort"]
                ),
            }
        else:
            context_budget = {}
        request_style = writer_profile["request_style"].strip().lower()
        tuner_thinking = writer_profile["thinking"]
        if request_style == "qwen" and tuner_thinking:
            payload["chat_template_kwargs"] = {
                "enable_thinking": tuner_thinking.strip().lower()
                in {"1", "true", "yes", "y", "on"}
            }
        elif request_style in {"deepseek_v4", "deepseek_v4_llamacpp"}:
            payload["chat_template_kwargs"] = {
                "thinking_mode": writer_profile["thinking_mode"] or "thinking",
                "reasoning_effort": writer_profile["reasoning_effort"] or "max",
            }
        elif request_style in {"dwarfstar", "ds4"}:
            thinking_mode = writer_profile["thinking_mode"].strip().lower()
            if thinking_mode:
                payload["think"] = thinking_mode not in {
                    "0", "false", "no", "off", "disabled", "none", "nothink"
                }
            if writer_profile["reasoning_effort"]:
                payload["reasoning_effort"] = writer_profile["reasoning_effort"]
        else:
            raise ValueError(f"unsupported writer request style: {request_style}")
        tuner_reasoning_format = writer_profile["reasoning_format"].strip()
        if request_style == "qwen" and tuner_reasoning_format:
            payload["reasoning_format"] = tuner_reasoning_format
        payload["cache_prompt"] = writer_profile["cache_prompt"].strip().lower() in {
            "1", "true", "yes", "y", "on"
        }
        if writer_profile["structured_output"].strip().lower() in {
            "1", "true", "yes", "y", "on"
        }:
            payload["response_format"] = self._json_schema_response_format(
                "oracle_sql_tuner_response",
                self.tuner_response_schema,
            )

        request = urllib.request.Request(
            f"{base_url}/chat/completions",
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )

        timeout = int(writer_profile["timeout_sec"])
        attempts = max(1, int(writer_profile["api_attempts"]))
        body: dict[str, Any] | None = None
        for attempt in range(1, attempts + 1):
            try:
                with self._urlopen(request, timeout=timeout) as response:
                    body = json.loads(response.read().decode("utf-8"))
                break
            except (OSError, ValueError, urllib.error.URLError) as exc:
                status_code = getattr(exc, "code", None)
                retryable = status_code is None or status_code == 429 or status_code >= 500
                if attempt >= attempts or not retryable:
                    raise RuntimeError(f"LLM API 호출 실패: {exc}") from exc
                self._log(
                    f"{writer_profile['label']} API attempt {attempt}/{attempts} "
                    f"failed: {exc}; retrying"
                )
                time.sleep(min(2**attempt, 5))

        if body is None:
            raise RuntimeError("LLM API returned no response")
        choices = body.get("choices")
        if not isinstance(choices, list) or not choices or not isinstance(choices[0], dict):
            raise RuntimeError("LLM API response has no choices")
        message = choices[0].get("message")
        if not isinstance(message, dict) or not isinstance(message.get("content"), str):
            raise RuntimeError("LLM API response has no message content")
        content = message["content"].strip()
        finish_reason = str(choices[0].get("finish_reason") or "")
        if finish_reason in {"length", "max_tokens"}:
            return {
                "sql": fallback_sql,
                "why": ["original_sql_returned_after_truncated_model_response"],
                "risk": [f"model_finish_reason={finish_reason}"],
                "check": ["reduce_reasoning_or_input_size_before_retry"],
                "raw_text": content,
                "request_config": self._generation_request_config(payload),
                "context_budget": context_budget,
                "usage": body.get("usage", {}),
            }
        try:
            parsed = self._extract_json_object(content)
        except (json.JSONDecodeError, ValueError) as exc:
            return {
                "sql": fallback_sql,
                "why": ["original_sql_returned_after_invalid_model_response"],
                "risk": [f"response_not_structured_json: {exc}"],
                "check": ["fix_model_response_format_before_retry"],
                "raw_text": content,
                "request_config": self._generation_request_config(payload),
                "context_budget": context_budget,
                "usage": body.get("usage", {}),
            }
        contract_errors = self._validate_json_contract(parsed, self.tuner_response_schema)
        if contract_errors:
            return {
                "sql": fallback_sql,
                "why": ["original_sql_returned_after_schema_validation_failure"],
                "risk": contract_errors,
                "check": ["fix_tuner_response_contract_before_retry"],
                "raw_text": content,
                "request_config": self._generation_request_config(payload),
                "context_budget": context_budget,
                "usage": body.get("usage", {}),
            }
        result = self._normalise_tuning_result(parsed, content)
        result["request_config"] = self._generation_request_config(payload)
        result["context_budget"] = context_budget
        result["usage"] = body.get("usage", {})
        return result

    def _make_local_tuning_draft(self, job: QueryJob, sql: str) -> dict[str, Any]:
        notes = job.findings or ["로컬 모드에서는 원문을 보존합니다."]
        critic_feedback = self._load_critic_feedback(job)
        header = [
            "/*",
            "AutorunEnum local tuning draft",
            "",
            "실제 LLM 튜닝을 원하면 --tuner llm 과 API_BASE_URL/MODEL_NAME을 설정하세요.",
            "",
            "Baseline:",
            json.dumps(job.metrics, ensure_ascii=False, indent=2),
            "",
            "Findings:",
            *(f"- {note}" for note in notes),
        ]
        if critic_feedback:
            header.extend(["", "Critic feedback:", critic_feedback.strip()])
        header.extend(["*/", ""])
        return {
            "sql": "\n".join(header) + sql,
            "why": notes,
            "risk": ["local_draft_does_not_rewrite_sql"],
            "check": ["run_with_tuner_llm_for_actual_rewrite"],
        }

    def _call_critic_model(
        self,
        job: QueryJob,
        critic: str,
        original_sql: str,
        tuned_sql: str,
    ) -> dict[str, Any]:
        self._refresh_critic_prompt()
        env_key = self._env_key(critic)
        base_url = (
            self._env(f"CRITIC_{env_key}_API_BASE_URL")
            or self._env("CRITIC_API_BASE_URL")
            or self._env("API_BASE_URL", "http://localhost:8080/v1")
        ).rstrip("/")
        api_key = (
            self._env(f"CRITIC_{env_key}_API_KEY")
            or self._env("CRITIC_API_KEY")
            or self._env("API_KEY", "sk-local")
        )
        model = (
            self._env(f"CRITIC_{env_key}_MODEL_NAME")
            or self._env("CRITIC_MODEL_NAME")
            or critic
        )
        temperature = float(
            self._env(f"CRITIC_{env_key}_TEMPERATURE")
            or self._env("CRITIC_TEMPERATURE", "0.0")
        )
        top_p_value = self._env(f"CRITIC_{env_key}_TOP_P") or self._env("CRITIC_TOP_P")
        top_k_value = self._env(f"CRITIC_{env_key}_TOP_K") or self._env("CRITIC_TOP_K")
        min_p_value = self._env(f"CRITIC_{env_key}_MIN_P") or self._env("CRITIC_MIN_P")
        presence_penalty_value = (
            self._env(f"CRITIC_{env_key}_PRESENCE_PENALTY")
            or self._env("CRITIC_PRESENCE_PENALTY")
        )
        frequency_penalty_value = (
            self._env(f"CRITIC_{env_key}_FREQUENCY_PENALTY")
            or self._env("CRITIC_FREQUENCY_PENALTY")
        )
        repetition_penalty_value = (
            self._env(f"CRITIC_{env_key}_REPETITION_PENALTY")
            or self._env("CRITIC_REPETITION_PENALTY")
        )
        seed_value = self._env(f"CRITIC_{env_key}_SEED") or self._env("CRITIC_SEED")
        thinking_value = (
            self._env(f"CRITIC_{env_key}_THINKING")
            or self._env("CRITIC_THINKING")
        )
        thinking_mode = (
            self._env(f"CRITIC_{env_key}_THINKING_MODE")
            or self._env("CRITIC_THINKING_MODE")
        )
        reasoning_effort = (
            self._env(f"CRITIC_{env_key}_REASONING_EFFORT")
            or self._env("CRITIC_REASONING_EFFORT")
        )
        request_style = (
            self._env(f"CRITIC_{env_key}_REQUEST_STYLE")
            or self._env("CRITIC_REQUEST_STYLE", "chat_template")
        ).strip().lower()
        timeout = int(self._env("CRITIC_TIMEOUT_SEC", "1800"))
        analysis_payload = self._load_json_file(self.analysis_dir / f"{job.name}.json")
        if not analysis_payload and job.analysis_path:
            analysis_payload = {"text": job.analysis_path.read_text(encoding="utf-8")}
        tuning_payload = self._load_json_file(self.tuning_dir / f"{job.name}-B.json")
        raw_tuner_result = (
            tuning_payload.get("llm_result", {})
            if isinstance(tuning_payload, dict)
            else {}
        )
        tuner_result = (
            {
                key: raw_tuner_result.get(key)
                for key in ("why", "risk", "check")
                if key in raw_tuner_result
            }
            if isinstance(raw_tuner_result, dict)
            else {}
        )
        critic_input = {
            "name": job.name,
            "analysis": analysis_payload,
            "baseline": job.metrics,
            "benchmark": job.benchmark,
            "tuner_result": tuner_result,
            "db_context": self._load_db_context(job),
            "original_sql": original_sql,
        }
        compact_tuned_sql, tuned_sql_is_duplicate = self._critic_tuned_sql_payload(
            original_sql,
            tuned_sql,
        )
        critic_input["tuned_sql"] = compact_tuned_sql
        critic_input["tuned_sql_is_duplicate"] = tuned_sql_is_duplicate

        payload = {
            "model": model,
            "temperature": temperature,
            "messages": [
                {
                    "role": "system",
                    "content": self.critic_prompt,
                },
                {
                    "role": "user",
                    "content": self._json_dumps(critic_input),
                },
            ],
        }
        max_tokens = int(
            self._env(f"CRITIC_{env_key}_MAX_TOKENS")
            or self._env("CRITIC_MAX_TOKENS", "2048")
        )
        if max_tokens > 0:
            payload["max_tokens"] = max_tokens
        if top_p_value:
            payload["top_p"] = float(top_p_value)
        if top_k_value:
            payload["top_k"] = int(top_k_value)
        if min_p_value:
            payload["min_p"] = float(min_p_value)
        if presence_penalty_value:
            payload["presence_penalty"] = float(presence_penalty_value)
        if frequency_penalty_value:
            payload["frequency_penalty"] = float(frequency_penalty_value)
        if repetition_penalty_value:
            payload["repeat_penalty"] = float(repetition_penalty_value)
        if seed_value:
            payload["seed"] = int(seed_value)
        if request_style in {"dwarfstar", "ds4"}:
            if thinking_value:
                payload["thinking"] = thinking_value.strip().lower() in {
                    "1",
                    "true",
                    "yes",
                    "y",
                    "on",
                }
            if reasoning_effort:
                payload["reasoning_effort"] = reasoning_effort
        elif request_style in {"deepseek_v4", "deepseek_v4_llamacpp"}:
            payload["chat_template_kwargs"] = {
                "thinking_mode": thinking_mode or "thinking",
                "reasoning_effort": reasoning_effort or "max",
            }
        elif request_style in {"hy3", "hy3_llamacpp"}:
            payload["chat_template_kwargs"] = {
                "reasoning_effort": reasoning_effort or "high"
            }
        elif request_style in {"nemotron", "nemotron_vllm"} and (
            thinking_value or reasoning_effort
        ):
            chat_template_kwargs = {}
            if thinking_value:
                chat_template_kwargs["enable_thinking"] = thinking_value.strip().lower() in {
                    "1",
                    "true",
                    "yes",
                    "y",
                    "on",
                }
            if reasoning_effort:
                chat_template_kwargs["reasoning_effort"] = reasoning_effort
            payload["chat_template_kwargs"] = chat_template_kwargs
        elif request_style in {"chat_template", "vllm", "default"} and (
            thinking_value or reasoning_effort
        ):
            chat_template_kwargs: dict[str, Any] = {}
            if thinking_value:
                chat_template_kwargs["thinking"] = thinking_value.strip().lower() in {
                    "1",
                    "true",
                    "yes",
                    "y",
                    "on",
                }
            if reasoning_effort:
                chat_template_kwargs["reasoning_effort"] = reasoning_effort
            payload["chat_template_kwargs"] = chat_template_kwargs
        elif request_style not in {
            "chat_template",
            "vllm",
            "default",
            "nemotron",
            "nemotron_vllm",
            "deepseek_v4",
            "deepseek_v4_llamacpp",
            "hy3",
            "hy3_llamacpp",
        }:
            raise ValueError(
                f"지원하지 않는 critic request style: {request_style}"
            )

        structured_output_env = self._env(f"CRITIC_{env_key}_STRUCTURED_OUTPUT")
        if structured_output_env:
            structured_output = structured_output_env.strip().lower() in {
                "1",
                "true",
                "yes",
                "y",
                "on",
            }
        elif request_style in {"dwarfstar", "ds4"}:
            # ds4-server compatibility is kept prompt-only unless explicitly enabled.
            structured_output = False
        else:
            structured_output = self._env_bool("CRITIC_STRUCTURED_OUTPUT", True)
        if structured_output:
            payload["response_format"] = self._json_schema_response_format(
                "oracle_sql_critic_response",
                self.critic_response_schema,
            )

        request = urllib.request.Request(
            f"{base_url}/chat/completions",
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )

        api_attempts = max(1, int(self._env("CRITIC_API_ATTEMPTS", "2")))
        body: dict[str, Any] | None = None
        for attempt in range(1, api_attempts + 1):
            try:
                with self._urlopen(request, timeout=timeout) as response:
                    body = json.loads(response.read().decode("utf-8"))
                break
            except urllib.error.URLError as exc:
                status_code = getattr(exc, "code", None)
                retryable = status_code is None or status_code == 429 or status_code >= 500
                if attempt >= api_attempts or not retryable:
                    raise RuntimeError(f"{critic} critic API 호출 실패: {exc}") from exc
                self._log(
                    f"{critic} critic API attempt {attempt}/{api_attempts} failed: "
                    f"{exc}; retrying"
                )
                time.sleep(min(2**attempt, 5))

        if body is None:
            raise RuntimeError(f"{critic} critic API returned no response")

        content = body["choices"][0]["message"]["content"].strip()
        parsed = self._extract_json_object(content)
        contract_errors = self._validate_json_contract(parsed, self.critic_response_schema)
        if contract_errors:
            raise ValueError("critic response contract failed: " + "; ".join(contract_errors))
        parsed["raw_text"] = content
        parsed["request_config"] = self._generation_request_config(payload)
        return parsed

    def _normalise_tuning_result(
        self,
        result: dict[str, Any],
        raw_text: str = "",
    ) -> dict[str, Any]:
        return {
            "sql": str(
                result.get("sql")
                or result.get("query")
                or result.get("optimized_sql")
                or result.get("tuned_sql")
                or ""
            ).strip(),
            "why": self._as_list(result.get("why") or result.get("reason")),
            "risk": self._as_list(result.get("risk") or result.get("risks")),
            "check": self._as_list(result.get("check") or result.get("checks")),
            "raw_text": raw_text,
            "request_config": result.get("request_config", {}),
        }

    def _normalise_critic_report(
        self,
        critic: str,
        report: dict[str, Any],
    ) -> dict[str, Any]:
        normalised = {
            "critic": critic,
            "approved": self._as_bool(report.get("ok", report.get("approved", False))),
            "risk_level": str(report.get("risk") or report.get("risk_level") or "medium"),
            "summary": str(report.get("sum") or report.get("summary") or ""),
            "blocking_issues": self._as_list(
                report.get("block") or report.get("blocking_issues")
            ),
            "improvement_suggestions": self._as_list(
                report.get("fix") or report.get("improvement_suggestions")
            ),
            "semantic_risks": self._as_list(report.get("sem") or report.get("semantic_risks")),
            "benchmark_notes": str(report.get("bench") or report.get("benchmark_notes") or ""),
            "raw_text": str(report.get("raw_text") or ""),
            "request_config": report.get("request_config", {}),
        }
        return normalised

    @staticmethod
    def _format_critic_report_text(report: dict[str, Any]) -> str:
        lines = [
            f"# Critic: {report['critic']}",
            "",
            f"- approved: {report['approved']}",
            f"- risk_level: {report['risk_level']}",
            f"- summary: {report['summary']}",
            "",
            "## Blocking Issues",
            *(f"- {item}" for item in report["blocking_issues"]),
            "",
            "## Improvement Suggestions",
            *(f"- {item}" for item in report["improvement_suggestions"]),
            "",
            "## Semantic Risks",
            *(f"- {item}" for item in report["semantic_risks"]),
            "",
            "## Benchmark Notes",
            report["benchmark_notes"] or "-",
        ]
        return "\n".join(lines) + "\n"

    @staticmethod
    def _format_feedback_block(report: dict[str, Any]) -> dict[str, Any]:
        return {
            "m": report["critic"],
            "ok": report["approved"],
            "risk": report["risk_level"],
            "sum": report["summary"],
            "block": report["blocking_issues"],
            "sem": report["semantic_risks"],
            "fix": report["improvement_suggestions"],
            "bench": report["benchmark_notes"],
        }

    def _job_passed_final_verification(self, job: QueryJob) -> bool:
        if getattr(job, "error", None):
            return False
        if getattr(self, "execute_benchmark", True) and job.benchmark.get("improved") is not True:
            return False
        if (
            self.require_critic_approval
            and job.benchmark.get("critic_approved") is not True
        ):
            return False
        if (
            self.require_oracle_validation
            and job.benchmark.get("oracle_validation_passed") is not True
        ):
            return False
        return True

    def _validate_sql_pair_with_oracle(
        self,
        job: QueryJob,
        original_sql: str,
        tuned_sql: str,
    ) -> dict[str, Any]:
        validation: dict[str, Any] = {
            "name": job.name,
            "mode": "oracle_parse_explain_sample",
            "passed": False,
            "failed_stage": None,
            "message": "",
            "checked_at": time.strftime("%Y-%m-%d %H:%M:%S"),
            "row_limit": self.validation_row_limit,
            "rules": self._oracle_validation_rules(),
            "steps": {},
            "snapshot": {},
            "sample_compare": {},
            "errors": [],
        }

        if not self._is_select_sql(original_sql) or not self._is_select_sql(tuned_sql):
            validation.update(
                {
                    "failed_stage": "select_guard",
                    "message": "Oracle 자동 검증은 SELECT/WITH SQL만 수행합니다.",
                }
            )
            return validation

        policy_violations = self._sql_safety_violations(tuned_sql)
        if policy_violations:
            validation["failed_stage"] = "sql_policy"
            validation["message"] = "튜닝 SQL이 materialization/result-cache 금지 규칙을 위반했습니다."
            validation["errors"].extend(
                {
                    "code": "SQL-POLICY",
                    "offset": None,
                    "message": violation,
                    "raw": violation,
                }
                for violation in policy_violations
            )
            return validation

        try:
            import oracledb
        except ImportError as exc:
            validation["failed_stage"] = "oracle_driver"
            validation["message"] = "python-oracledb가 설치되어 있지 않습니다."
            validation["errors"].append(self._oracle_error_payload(exc))
            return validation

        user = self._env("ORACLE_USER")
        password = self._env("ORACLE_PASSWORD")
        dsn = self._env("ORACLE_DSN")
        if not user or not password or not dsn:
            validation["failed_stage"] = "oracle_connection_config"
            validation["message"] = "ORACLE_USER, ORACLE_PASSWORD, ORACLE_DSN 필요"
            return validation

        try:
            with oracledb.connect(user=user, password=password, dsn=dsn) as connection:
                connection.call_timeout = self.oracle_call_timeout_ms
                with connection.cursor() as cursor:
                    self._apply_oracle_session(cursor, job)
                    original_check = self._validate_single_sql(
                        cursor,
                        original_sql,
                        job.name,
                        "orig",
                        reject_materialization=False,
                    )
                    tuned_check = self._validate_single_sql(
                        cursor,
                        tuned_sql,
                        job.name,
                        "tuned",
                        reject_materialization=True,
                    )
                    validation["steps"]["original"] = original_check
                    validation["steps"]["tuned"] = tuned_check

                    if not original_check["ok"]:
                        validation["failed_stage"] = "original_parse_explain"
                        validation["message"] = "원본 SQL도 Oracle parse/explain 검증을 통과하지 못했습니다."
                        validation["errors"].extend(original_check["errors"])
                        return validation

                    if not tuned_check["ok"]:
                        validation["failed_stage"] = "tuned_parse_explain"
                        validation["message"] = "튜닝 SQL이 Oracle parse/explain 검증을 통과하지 못했습니다."
                        validation["errors"].extend(tuned_check["errors"])
                        return validation

                    connection.commit()
                    if self._env_bool("SAME_SNAPSHOT_VALIDATION", True):
                        try:
                            cursor.execute("SET TRANSACTION READ ONLY")
                            validation["snapshot"] = {
                                "mode": "read_only_transaction",
                                "same_snapshot": True,
                            }
                        except Exception as exc:
                            validation["failed_stage"] = "snapshot_setup"
                            validation["message"] = (
                                "동일 스냅샷 검증을 위한 read-only transaction 설정에 실패했습니다."
                            )
                            validation["errors"].append(self._oracle_error_payload(exc))
                            return validation
                    else:
                        validation["snapshot"] = {
                            "mode": "statement_read_consistency",
                            "same_snapshot": False,
                        }

                    sample_compare = self._compare_sql_samples(
                        cursor, job, original_sql, tuned_sql
                    )
                    validation["sample_compare"] = sample_compare
                    if not sample_compare["passed"]:
                        validation["failed_stage"] = "sample_compare"
                        validation["message"] = "원본/튜닝 SQL 샘플 결과가 일치하지 않습니다."
                        validation["errors"].extend(sample_compare.get("errors", []))
                        return validation
                    connection.rollback()

        except Exception as exc:
            validation["failed_stage"] = "oracle_runtime"
            validation["message"] = f"Oracle 검증 실행 실패: {exc}"
            validation["errors"].append(self._oracle_error_payload(exc))
            return validation

        validation["passed"] = True
        validation["message"] = "검증 통과"
        return validation

    def _validate_single_sql(
        self,
        cursor: Any,
        sql: str,
        job_name: str,
        label: str,
        reject_materialization: bool = False,
    ) -> dict[str, Any]:
        result: dict[str, Any] = {
            "ok": False,
            "parse": {"ok": False},
            "explain": {"ok": False, "plan": []},
            "errors": [],
        }
        clean_sql = sql.strip().rstrip(";")

        try:
            cursor.prepare(clean_sql)
            result["parse"]["ok"] = True
        except Exception as exc:
            result["parse"]["error"] = self._oracle_error_payload(exc)
            result["errors"].append(result["parse"]["error"])
            return result

        statement_id = self._statement_id(job_name, label)
        try:
            cursor.execute(f"EXPLAIN PLAN SET STATEMENT_ID = '{statement_id}' FOR {clean_sql}")
            result["explain"]["ok"] = True
            result["explain"]["statement_id"] = statement_id
            result["explain"]["plan"] = self._fetch_explain_plan(cursor, statement_id)
            forbidden_operations = self._forbidden_plan_operations(
                result["explain"]["plan"]
            )
            result["explain"]["forbidden_operations"] = forbidden_operations
            if reject_materialization and forbidden_operations:
                result["explain"]["ok"] = False
                message = (
                    "Forbidden materialization plan operation(s): "
                    + ", ".join(forbidden_operations)
                )
                result["errors"].append(
                    {
                        "code": "PLAN-MATERIALIZATION",
                        "offset": None,
                        "message": message,
                        "raw": message,
                    }
                )
                return result
        except Exception as exc:
            result["explain"]["error"] = self._oracle_error_payload(exc)
            result["errors"].append(result["explain"]["error"])
            return result

        result["ok"] = result["parse"]["ok"] and result["explain"]["ok"]
        return result

    @staticmethod
    def _apply_oracle_session(cursor: Any, job: QueryJob) -> None:
        schema = str(getattr(job, "parsing_schema_name", "") or "").strip()
        if not schema:
            return
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_$#]{0,127}", schema):
            raise RuntimeError(f"invalid Oracle parsing schema name: {schema!r}")
        cursor.execute(f'ALTER SESSION SET CURRENT_SCHEMA = "{schema.upper()}"')

    def _fetch_explain_plan(self, cursor: Any, statement_id: str) -> list[str]:
        cursor.execute(
            "SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY(NULL, :sid, 'BASIC +PREDICATE +ALIAS'))",
            sid=statement_id,
        )
        plan = [str(row[0]) for row in cursor.fetchall()]
        if not plan:
            raise RuntimeError(f"DBMS_XPLAN returned no rows for statement_id={statement_id}")
        return plan

    @staticmethod
    def _forbidden_plan_operations(plan: list[str]) -> list[str]:
        plan_text = "\n".join(str(line) for line in plan).upper()
        forbidden = [
            "TEMP TABLE TRANSFORMATION",
            "LOAD AS SELECT",
            "CURSOR DURATION MEMORY",
        ]
        return [operation for operation in forbidden if operation in plan_text]

    @staticmethod
    def _prohibited_sql_features(sql: str) -> list[str]:
        checks = [
            (r"\bMATERIALIZED\b", "MATERIALIZED keyword is prohibited"),
            (r"/\*\+[\s\S]*?\bMATERIALIZE\b[\s\S]*?\*/", "MATERIALIZE hint is prohibited"),
            (r"\bRESULT_CACHE\b", "RESULT_CACHE usage is prohibited"),
        ]
        return [
            message
            for pattern, message in checks
            if re.search(pattern, sql, re.IGNORECASE)
        ]

    @classmethod
    def _sql_safety_violations(cls, sql: str) -> list[str]:
        clean = cls._strip_sql_comments(sql)
        violations = cls._prohibited_sql_features(clean)
        if not cls._is_select_sql(clean):
            violations.append("only a single SELECT/WITH statement is allowed")
        masked = cls._mask_sql_literals(clean)
        if ";" in masked.rstrip(";"):
            violations.append("multiple SQL statements are prohibited")
        if re.search(
            r"\b(?:DBMS_LOCK|DBMS_PIPE|UTL_HTTP|UTL_TCP|UTL_INADDR|HTTPURITYPE|DBMS_SCHEDULER)\b",
            masked,
            re.IGNORECASE,
        ):
            violations.append("side-effecting or network-capable package usage is prohibited")
        return violations

    @staticmethod
    def _mask_sql_literals(sql: str) -> str:
        # Preserve character positions while preventing bind/semicolon detection in literals.
        return re.sub(r"'(?:''|[^'])*'", lambda match: " " * len(match.group(0)), sql)

    def _execution_binds(
        self, job: QueryJob, original_sql: str, tuned_sql: str
    ) -> dict[str, Any]:
        bind_pattern = r"(?<!:):([A-Za-z][A-Za-z0-9_$#]*|[0-9]+)"
        original_clean = self._mask_sql_literals(self._strip_sql_comments(original_sql))
        tuned_clean = self._mask_sql_literals(self._strip_sql_comments(tuned_sql))
        original_names = set(re.findall(bind_pattern, original_clean))
        tuned_names = set(re.findall(bind_pattern, tuned_clean))
        if original_names != tuned_names:
            raise RuntimeError(
                "original/tuned bind names differ: "
                f"original={sorted(original_names)}, tuned={sorted(tuned_names)}"
            )
        if not original_names:
            return {}

        query_context = self._load_db_context(job).get("query", {})
        configured = query_context.get("binds", []) if isinstance(query_context, dict) else []
        values: dict[str, Any] = {}
        for item in configured:
            if not isinstance(item, dict):
                continue
            name = str(item.get("name") or item.get("position") or "").lstrip(":")
            if name and "value" in item:
                values[name] = item["value"]
        missing = original_names - values.keys()
        if missing:
            raise RuntimeError(
                "missing execution bind values in query context: " + ", ".join(sorted(missing))
            )
        return {name: values[name] for name in original_names}

    def _compare_sql_samples(
        self, cursor: Any, job: QueryJob, original_sql: str, tuned_sql: str
    ) -> dict[str, Any]:
        result: dict[str, Any] = {
            "passed": False,
            "original": {},
            "tuned": {},
            "checks": {},
            "errors": [],
        }
        try:
            binds = self._execution_binds(job, original_sql, tuned_sql)
            original_sample = self._sample_select(cursor, original_sql, binds)
            tuned_sample = self._sample_select(cursor, tuned_sql, binds)
        except Exception as exc:
            result["errors"].append(self._oracle_error_payload(exc))
            return result

        result["original"] = original_sample
        result["tuned"] = tuned_sample
        checks = {
            "columns_match": original_sample["columns"] == tuned_sample["columns"],
            "limited_row_count_match": original_sample["row_count"] == tuned_sample["row_count"],
            "ordered_hash_match": original_sample["ordered_hash"] == tuned_sample["ordered_hash"],
            "unordered_hash_match": original_sample["unordered_hash"] == tuned_sample["unordered_hash"],
            "complete_results": original_sample["complete"] and tuned_sample["complete"],
            "order_preservation_required": self._requires_order_preservation(
                original_sql
            ),
        }
        result["checks"] = checks
        result["passed"] = (
            checks["columns_match"]
            and checks["limited_row_count_match"]
            and checks["unordered_hash_match"]
            and checks["complete_results"]
            and (
                not checks["order_preservation_required"]
                or checks["ordered_hash_match"]
            )
        )
        return result

    def _sample_select(self, cursor: Any, sql: str, binds: dict[str, Any]) -> dict[str, Any]:
        start = time.perf_counter()
        cursor.execute(sql.strip().rstrip(";"), dict(binds))
        columns = [str(col[0]) for col in cursor.description]
        max_rows = max(1, self.validation_row_limit)
        ordered_hasher = hashlib.sha256()
        unordered_accumulator = 0
        modulus = 1 << 256
        row_count = 0
        sample_rows: list[list[Any]] = []

        if hasattr(cursor, "fetchmany"):
            def row_batches():
                while True:
                    batch = cursor.fetchmany(min(1000, max_rows + 1))
                    if not batch:
                        break
                    yield batch
        else:
            def row_batches():
                yield cursor.fetchall()

        truncated = False
        for rows in row_batches():
            for row in rows:
                row_count += 1
                if row_count > max_rows:
                    truncated = True
                    break
                normalised = [self._normalise_cell(value) for value in row]
                row_json = self._json_dumps(normalised).encode("utf-8")
                ordered_hasher.update(len(row_json).to_bytes(8, "big"))
                ordered_hasher.update(row_json)
                unordered_accumulator = (
                    unordered_accumulator
                    + int.from_bytes(hashlib.sha256(row_json).digest(), "big")
                ) % modulus
                if getattr(self, "store_sample_rows", False) and len(sample_rows) < 3:
                    sample_rows.append(normalised)
            if truncated:
                break

        elapsed_ms = (time.perf_counter() - start) * 1000.0
        return {
            "columns": columns,
            "row_count": min(row_count, max_rows),
            "complete": not truncated,
            "ordered_hash": ordered_hasher.hexdigest(),
            "unordered_hash": f"{unordered_accumulator:064x}",
            "sample_rows": sample_rows,
            "elapsed_ms": round(elapsed_ms, 4),
        }

    @staticmethod
    def _normalise_cell(value: Any) -> Any:
        if value is None:
            return None
        if hasattr(value, "isoformat"):
            return value.isoformat()
        if isinstance(value, (bytes, bytearray)):
            return value.hex()
        if isinstance(value, (int, float, str, bool)):
            return value
        return str(value)

    def _rows_hash(self, rows: list[list[Any]]) -> str:
        body = self._json_dumps(rows)
        return hashlib.sha256(body.encode("utf-8")).hexdigest()

    @classmethod
    def _requires_order_preservation(cls, sql: str) -> bool:
        clean = cls._mask_sql_literals(cls._strip_sql_comments(sql))
        return bool(
            re.search(
                r"\bORDER\s+BY\b|\bFETCH\s+(?:FIRST|NEXT)\b|\bOFFSET\b|\bROWNUM\b",
                clean,
                re.IGNORECASE,
            )
        )

    @staticmethod
    def _statement_id(job_name: str, label: str) -> str:
        digest = hashlib.sha1(f"{job_name}:{label}:{time.time_ns()}".encode("utf-8")).hexdigest()
        return f"LLMSQL_{label[:1].upper()}_{digest[:20]}"

    @staticmethod
    def _oracle_validation_rules() -> list[str]:
        return [
            "sql_field_contains_sql_only",
            "oracle_19c_syntax_only",
            "no_same_select_alias_reuse",
            "no_rownum_eq_1_order_by",
            "aggregate_alias_only_in_outer_select",
            "no_materialized_keyword_or_materialize_hint",
            "no_result_cache",
            "reject_temp_table_transformation",
            "explain_plan_before_execution",
            "same_snapshot_row_count_hash_sample_compare",
        ]

    @staticmethod
    def _oracle_error_payload(exc: Exception) -> dict[str, Any]:
        raw = str(exc)
        first_arg = exc.args[0] if getattr(exc, "args", None) else None
        message = str(getattr(first_arg, "message", raw))
        code = getattr(first_arg, "code", None)
        offset = getattr(first_arg, "offset", None)
        match = re.search(r"(ORA-\d+)", message or raw)
        return {
            "code": f"ORA-{code:05d}" if isinstance(code, int) else (match.group(1) if match else None),
            "offset": offset,
            "message": message or raw,
            "raw": raw,
        }

    def _merge_feedback_payload(self, job: QueryJob, patch: dict[str, Any]) -> None:
        feedback_path = self.feedback_dir / f"{job.name}.json"
        payload = self._load_json_file(feedback_path)
        if not isinstance(payload, dict) or not payload:
            payload = {"name": job.name, "ok": True, "critics": []}
        payload.update(patch)
        payload["ok"] = bool(payload.get("ok", True)) and all(
            block.get("ok", True)
            for key, block in payload.items()
            if isinstance(block, dict) and key != "critics"
        )
        job.feedback_path = feedback_path
        feedback_path.write_text(self._json_dumps(payload), encoding="utf-8")

    def _load_critic_feedback(self, job: QueryJob) -> str:
        payload = self._load_critic_feedback_payload(job)
        if payload:
            return self._json_dumps(payload)
        # LEGACY (disabled): feedback was previously read from a free-form .txt file.
        # Machine feedback is JSON-only so retry behavior remains deterministic.
        # legacy_feedback_path = self.feedback_dir / f"{job.name}.txt"
        # if legacy_feedback_path.exists():
        #     job.feedback_path = legacy_feedback_path
        #     return legacy_feedback_path.read_text(encoding="utf-8")
        return ""

    def _load_critic_feedback_payload(self, job: QueryJob) -> dict[str, Any]:
        feedback_path = self.feedback_dir / f"{job.name}.json"
        if feedback_path.exists():
            job.feedback_path = feedback_path
            payload = self._load_json_file(feedback_path)
            return payload if isinstance(payload, dict) else {}
        return {}

    def _wait_for_manual_model_swap(self, role: str, model: str, base_url: str) -> None:
        if not self.manual_model_swap:
            return

        message = (
            f"[MANUAL_MODEL_SWAP] {role} 단계입니다. "
            f"모델 서버를 '{model}'로 맞추고 endpoint '{base_url}'가 준비되면 Enter를 누르세요."
        )
        if not sys.stdin.isatty():
            raise RuntimeError(
                "MANUAL_MODEL_SWAP=1은 대화형 터미널에서만 사용할 수 있습니다. "
                f"{message}"
            )
        input(message + "\n")
        self._log(f"{role}: model endpoint confirmed; requests will now start")

    def _ensure_model_endpoint(self, role: str, model: str, base_url: str) -> None:
        if self._model_endpoint_ready(base_url, model):
            self._log(f"{role}: model '{model}' is already ready")
            return

        if self.manual_model_swap:
            self._wait_for_manual_model_swap(role, model, base_url)
            if not self._model_endpoint_ready(base_url, model):
                raise RuntimeError(
                    f"{role}: endpoint {base_url} does not serve expected model '{model}'"
                )
            return

        env_name = "TUNER_START_SCRIPT"
        if role.startswith("critic:"):
            critic = role.split(":", 1)[1]
            env_name = f"CRITIC_{self._env_key(critic)}_START_SCRIPT"
        elif role.startswith("writer:"):
            env_name = "FINAL_WRITER_START_SCRIPT"
        start_script_raw = self._env(env_name)
        if not self.auto_model_swap or not start_script_raw:
            raise RuntimeError(
                f"{role}: expected model '{model}' is not ready at {base_url}; "
                f"enable AUTO_MODEL_SWAP=1 and set {env_name}"
            )

        start_script = Path(start_script_raw).expanduser()
        if not start_script.is_absolute():
            start_script = REPO_ROOT / start_script
        start_script = start_script.resolve()
        if not start_script.is_file():
            raise RuntimeError(f"{role}: model launcher not found: {start_script}")

        self._log(f"{role}: switching to model '{model}' via {start_script}")
        try:
            subprocess.run(
                [str(start_script)],
                cwd=str(start_script.parent),
                check=True,
                timeout=int(self._env("MODEL_LAUNCH_TIMEOUT_SEC", "1800")),
            )
        except (OSError, subprocess.SubprocessError) as exc:
            raise RuntimeError(f"{role}: model launcher failed: {exc}") from exc

        timeout = max(1, int(self._env("MODEL_START_TIMEOUT_SEC", "7200")))
        started_at = time.monotonic()
        next_notice = 0.0
        while not self._model_endpoint_ready(base_url, model):
            elapsed = time.monotonic() - started_at
            if elapsed >= timeout:
                raise RuntimeError(
                    f"{role}: model '{model}' was not ready within {timeout}s"
                )
            if elapsed >= next_notice:
                self._log(
                    f"{role}: waiting for model '{model}' "
                    f"({elapsed:.0f}s/{timeout}s)"
                )
                next_notice = elapsed + 30
            time.sleep(5)
        self._log(f"{role}: model '{model}' is ready")

    @staticmethod
    def _model_endpoint_ready(base_url: str, expected_model: str) -> bool:
        try:
            with urllib.request.urlopen(
                f"{base_url.rstrip('/')}/models", timeout=5
            ) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except (OSError, ValueError, urllib.error.URLError):
            return False
        model_ids = {
            str(item.get("id") or item.get("name") or item.get("model") or "")
            for key in ("data", "models")
            for item in payload.get(key, [])
            if isinstance(item, dict)
        }
        return expected_model in model_ids

    @staticmethod
    def _urlopen(
        request: str | urllib.request.Request,
        timeout: int,
    ):
        return urllib.request.urlopen(request, timeout=timeout)

    @staticmethod
    def _estimate_tokens(text: str) -> int:
        # Conservative tokenizer-independent estimate for mixed Korean, English,
        # JSON and Oracle SQL. The server still performs the authoritative count.
        if not text:
            return 0
        non_ascii = sum(1 for char in text if ord(char) > 127)
        ascii_count = len(text) - non_ascii
        return max(1, (ascii_count + 3) // 4 + non_ascii)

    @staticmethod
    def _extract_json_object(text: str) -> dict[str, Any]:
        fenced = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
        candidate = fenced.group(1) if fenced else text
        start = candidate.find("{")
        end = candidate.rfind("}")
        if start >= 0 and end >= start:
            candidate = candidate[start : end + 1]
        parsed = json.loads(candidate)
        if not isinstance(parsed, dict):
            raise ValueError("critic response JSON must be an object")
        return parsed

    @staticmethod
    def _as_list(value: Any) -> list[str]:
        if value is None:
            return []
        if isinstance(value, list):
            return [str(item) for item in value]
        return [str(value)]

    @staticmethod
    def _as_bool(value: Any) -> bool:
        if isinstance(value, bool):
            return value
        if isinstance(value, str):
            return value.strip().lower() in {"1", "true", "yes", "y", "approved", "pass"}
        return bool(value)

    def _parse_critics(self, explicit: str = "") -> list[str]:
        raw = explicit or self._env("CRITIC_MODELS", "")
        critics: list[str] = []
        for item in raw.split(","):
            critic = item.strip()
            if critic and critic not in critics:
                critics.append(critic)
        return critics

    @staticmethod
    def _env_key(name: str) -> str:
        return re.sub(r"[^A-Z0-9]+", "_", name.upper()).strip("_")

    def _run_select_benchmark(
        self, job: QueryJob, original_sql: str, tuned_sql: str
    ) -> dict[str, Any]:
        result: dict[str, Any] = {
            "tuned": {},
            "improvement_pct": None,
            "improved": False,
            "needs_review": True,
            "benchmark_mode": self.benchmark_mode,
        }

        original_clean = original_sql.strip().rstrip(";")
        tuned_clean = tuned_sql.strip().rstrip(";")

        if not self._is_select_sql(original_clean) or not self._is_select_sql(tuned_clean):
            result["message"] = "SELECT SQL만 자동 벤치마크합니다."
            return result

        policy_violations = self._sql_safety_violations(tuned_clean)
        if policy_violations:
            result["message"] = "; ".join(policy_violations)
            return result

        try:
            original_samples, tuned_samples = self._time_select_pair(
                job, original_clean, tuned_clean
            )
        except Exception as exc:
            result["message"] = f"벤치마크 실행 실패: {exc}"
            return result

        original_ms = statistics.median(original_samples)
        tuned_ms = statistics.median(tuned_samples)
        improvement_pct = ((original_ms - tuned_ms) / original_ms) * 100 if original_ms else 0.0
        improved = improvement_pct >= self.improvement_threshold_pct
        result.update(
            {
                "original": {
                    "median_elapsed_ms": round(original_ms, 4),
                    "samples_ms": original_samples,
                },
                "tuned": {
                    "median_elapsed_ms": round(tuned_ms, 4),
                    "samples_ms": tuned_samples,
                },
                "improvement_pct": round(improvement_pct, 4),
                "improved": improved,
                "needs_review": not improved,
                "message": "개선 성공" if improved else "개선 기준 미달",
            }
        )
        return result

    def _time_select_pair(
        self, job: QueryJob, original_sql: str, tuned_sql: str
    ) -> tuple[list[float], list[float]]:
        try:
            import oracledb
        except ImportError as exc:
            raise RuntimeError("python-oracledb가 설치되어 있지 않습니다.") from exc

        user = self._env("ORACLE_USER")
        password = self._env("ORACLE_PASSWORD")
        dsn = self._env("ORACLE_DSN")

        if not user or not password or not dsn:
            raise RuntimeError("ORACLE_USER, ORACLE_PASSWORD, ORACLE_DSN 필요")

        with oracledb.connect(user=user, password=password, dsn=dsn) as connection:
            connection.call_timeout = self.oracle_call_timeout_ms
            with connection.cursor() as cursor:
                self._apply_oracle_session(cursor, job)
                if self._env_bool("SAME_SNAPSHOT_VALIDATION", True):
                    cursor.execute("SET TRANSACTION READ ONLY")
                binds = self._execution_binds(job, original_sql, tuned_sql)
                execute_binds = dict(binds)
                if self.benchmark_mode == "first_n":
                    execute_binds["llmsql_row_limit"] = self.benchmark_row_limit
                    original_statement = (
                        f"SELECT * FROM ({original_sql.rstrip(';')}) "
                        "WHERE ROWNUM <= :llmsql_row_limit"
                    )
                    tuned_statement = (
                        f"SELECT * FROM ({tuned_sql.rstrip(';')}) "
                        "WHERE ROWNUM <= :llmsql_row_limit"
                    )
                else:
                    original_statement = original_sql.rstrip(";")
                    tuned_statement = tuned_sql.rstrip(";")
                samples: dict[str, list[float]] = {"original": [], "tuned": []}
                for index in range(self.benchmark_repetitions + 1):
                    order = (
                        ("original", original_statement),
                        ("tuned", tuned_statement),
                    )
                    if index % 2:
                        order = tuple(reversed(order))
                    for label, statement in order:
                        start = time.perf_counter()
                        cursor.execute(statement, execute_binds)
                        while cursor.fetchmany(1000):
                            pass
                        elapsed = (time.perf_counter() - start) * 1000.0
                        if index:
                            samples[label].append(round(elapsed, 4))
                connection.rollback()
                return samples["original"], samples["tuned"]

    @staticmethod
    def extract_tables(sql: str) -> list[str]:
        pattern = r"\b(?:FROM|JOIN|UPDATE|INTO)\s+([A-Z0-9_$#@.\"]+)"
        tables: list[str] = []

        for match in re.findall(pattern, sql.upper()):
            local_ref = match.split("@")[0]
            table = ".".join(
                part.strip('"')
                for part in local_ref.split(".")
                if part.strip('"')
            )
            if table and table not in tables:
                tables.append(table)

        return tables

    @staticmethod
    def find_static_findings(sql: str) -> list[str]:
        findings: list[str] = []

        if re.search(r"\bSELECT\s+\*", sql, re.IGNORECASE):
            findings.append("SELECT * 사용: 필요한 컬럼만 명시하는지 검토 필요")

        if re.search(r"@[A-Z0-9_]+", sql, re.IGNORECASE):
            findings.append("DB Link 사용: 원격 테이블은 CTE로 1회 수집 후 조인 권장")

        if re.search(r"\bFROM\b[^;]+,\s*[A-Z0-9_$#.\"]+", sql, re.IGNORECASE | re.DOTALL):
            findings.append("암시적 콤마 조인 감지: ANSI JOIN 전환 권장")

        scalar_subqueries = len(re.findall(r"\(\s*SELECT\b", sql, re.IGNORECASE))
        if scalar_subqueries:
            findings.append(
                f"스칼라 서브쿼리 후보 {scalar_subqueries}개: N+1 및 ORA-01427 위험 검토"
            )

        if re.search(r"\bTO_CHAR\s*\(\s*SYSDATE", sql, re.IGNORECASE):
            findings.append("SYSDATE 문자열 변환 반복: 1회 계산 후 재사용 권장")

        if re.search(r"\bROWNUM\s*=\s*1\b[\s\S]*\bORDER\s+BY\b", sql, re.IGNORECASE):
            findings.append("ROWNUM = 1 과 ORDER BY 동일 블록 사용 위험: 정렬 후 바깥 SELECT에서 ROWNUM 적용 필요")

        if re.search(r"\bGROUP\s+BY\b[\s\S]*\bHAVING\b[\s\S]*\b[A-Z0-9_]+_?(?:CNT|COUNT|SUM|AVG|MAX|MIN)\b", sql, re.IGNORECASE):
            findings.append("집계 alias 재참조 가능성: 집계 alias는 바깥 SELECT에서만 참조 권장")

        return findings

    @staticmethod
    def _strip_sql_comments(sql: str) -> str:
        output: list[str] = []
        index = 0
        state = "normal"
        while index < len(sql):
            char = sql[index]
            next_char = sql[index + 1] if index + 1 < len(sql) else ""

            if state == "normal":
                if char == "'":
                    state = "single_quote"
                    output.append(char)
                elif char == '"':
                    state = "double_quote"
                    output.append(char)
                elif char == "-" and next_char == "-":
                    state = "line_comment"
                    output.extend((" ", " "))
                    index += 1
                elif char == "/" and next_char == "*":
                    state = "block_comment"
                    output.extend((" ", " "))
                    index += 1
                else:
                    output.append(char)
            elif state == "single_quote":
                output.append(char)
                if char == "'" and next_char == "'":
                    output.append(next_char)
                    index += 1
                elif char == "'":
                    state = "normal"
            elif state == "double_quote":
                output.append(char)
                if char == '"' and next_char == '"':
                    output.append(next_char)
                    index += 1
                elif char == '"':
                    state = "normal"
            elif state == "line_comment":
                if char in "\r\n":
                    output.append(char)
                    state = "normal"
                else:
                    output.append(" ")
            elif state == "block_comment":
                if char == "*" and next_char == "/":
                    output.extend((" ", " "))
                    index += 1
                    state = "normal"
                else:
                    output.append(char if char in "\r\n" else " ")
            index += 1
        return "".join(output).strip().rstrip(";")

    @classmethod
    def _critic_tuned_sql_payload(
        cls,
        original_sql: str,
        tuned_sql: str,
    ) -> tuple[str, bool]:
        is_duplicate = cls._strip_sql_comments(original_sql) == cls._strip_sql_comments(
            tuned_sql
        )
        if is_duplicate:
            return (
                "[UNCHANGED: tuned_sql is semantically identical to original_sql; "
                "the full duplicate text was omitted to preserve model context.]",
                True,
            )
        return tuned_sql, False

    @staticmethod
    def _is_select_sql(sql: str) -> bool:
        without_comments = PipelineManager._strip_sql_comments(sql)
        return bool(re.match(r"^\s*(WITH|SELECT)\b", without_comments, re.IGNORECASE))

    @staticmethod
    def _format_metrics(metrics: dict[str, Any]) -> list[str]:
        if not metrics:
            return ["- No baseline metrics."]
        return [f"- {key}: {value}" for key, value in metrics.items()]

    def _read_sql(self, job: QueryJob) -> str:
        return job.input_path.read_text(encoding="utf-8")

    @staticmethod
    def _json_dumps(payload: Any, pretty: bool = False) -> str:
        if pretty:
            return json.dumps(payload, ensure_ascii=False, indent=2)
        return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))

    def _load_json_file(self, path: Path) -> Any:
        if not path.exists():
            return {}
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return {}

    def _write_status(self) -> None:
        status_path = self.workspace / "status.json"
        self._atomic_write_text(
            status_path,
            self._json_dumps([job.to_dict() for job in self.jobs], pretty=True),
        )

    def _write_summary(self, result: str) -> None:
        summary = {
            "result": result,
            "workspace": str(self.workspace),
            "mode": self.mode,
            "tuner": self._active_tuner_name(),
            "critics": self.critics,
            "prompts": {
                "tuner": self.tuner_prompt_meta,
                "critic": self.critic_prompt_meta,
                "deepseek_agent": self.deepseek_agent_prompt_meta,
            },
            "response_schemas": {
                "tuner": self.tuner_response_schema_meta,
                "critic": self.critic_response_schema_meta,
                "db_catalog": self.db_catalog_schema_meta,
                "db_query_context": self.db_query_context_schema_meta,
            },
            "structured_output": {
                "tuner": self._env_bool("TUNER_STRUCTURED_OUTPUT", True),
                "critic_default": self._env_bool("CRITIC_STRUCTURED_OUTPUT", True),
            },
            "same_snapshot_validation": self._env_bool(
                "SAME_SNAPSHOT_VALIDATION",
                True,
            ),
            "require_critic_approval": self.require_critic_approval,
            "oracle_validate": self.oracle_validate,
            "require_oracle_validation": self.require_oracle_validation,
            "validation_row_limit": self.validation_row_limit,
            "benchmark_repetitions": self.benchmark_repetitions,
            "oracle_call_timeout_ms": self.oracle_call_timeout_ms,
            "job_count": len(self.jobs),
            "jobs": [job.to_dict() for job in self.jobs],
        }
        summary_path = self.workspace / "summary.json"
        self._atomic_write_text(
            summary_path,
            self._json_dumps(summary, pretty=True),
        )

    @staticmethod
    def _atomic_write_text(path: Path, content: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{path.name}.",
            suffix=".tmp",
            dir=path.parent,
        )
        temporary_path = Path(temporary_name)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
            os.chmod(temporary_path, 0o600)
            os.replace(temporary_path, path)
        finally:
            temporary_path.unlink(missing_ok=True)

    def _env(self, name: str, default: str = "") -> str:
        value = os.getenv(name)
        if value is not None:
            return value

        env_paths = []
        explicit_env = os.getenv("AUTORUN_ENV_FILE", "").strip()
        if explicit_env:
            env_paths.append(Path(explicit_env).expanduser())
        env_paths.extend([
            SCRIPT_DIR / ".env",
            REPO_ROOT / ".env",
            self.workspace.parent / ".env",
            self.workspace.parent.parent / ".env",
            Path.cwd() / ".env",
        ])

        seen_env_paths: set[Path] = set()
        for env_path in env_paths:
            env_path = env_path.resolve()
            if env_path in seen_env_paths:
                continue
            seen_env_paths.add(env_path)
            if not env_path.exists():
                continue

            for line in env_path.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, raw_value = line.split("=", 1)
                if key.strip() == name:
                    return raw_value.strip().strip('"').strip("'")

        return default

    def _env_bool(self, name: str, default: bool = False) -> bool:
        value = self._env(name)
        if value == "":
            return default
        return value.strip().lower() in {"1", "true", "yes", "y", "on"}

    def _log(self, message: str) -> None:
        print(f"[AutorunEnum] {message}", flush=True)

    def close(self) -> None:
        lock_fd = getattr(self, "_workspace_lock_fd", -1)
        if lock_fd < 0:
            return
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_UN)
        finally:
            os.close(lock_fd)
            self._workspace_lock_fd = -1

    def __del__(self) -> None:
        try:
            self.close()
        except Exception:
            pass
