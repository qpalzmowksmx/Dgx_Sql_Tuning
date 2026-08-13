from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


AUTORUN_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = AUTORUN_DIR.parent
sys.path.insert(0, str(AUTORUN_DIR))

from PipelineManager import PipelineManager  # noqa: E402
from QueryJob import QueryJob  # noqa: E402
from EnumAuto import QueryStatus  # noqa: E402
from main import run_pipeline  # noqa: E402


class PipelineContractTests(unittest.TestCase):
    def load_json(self, relative_path: str) -> dict:
        return json.loads((REPO_ROOT / relative_path).read_text(encoding="utf-8"))

    def test_response_contracts_accept_expected_payloads(self) -> None:
        tuner_schema = self.load_json("contracts/tuner_response.schema.json")
        critic_schema = self.load_json("contracts/critic_response.schema.json")

        tuner_payload = {
            "sql": "SELECT 1 FROM dual",
            "why": [],
            "risk": [],
            "check": [],
        }
        critic_payload = {
            "ok": True,
            "risk": "low",
            "sum": "Safe to validate.",
            "block": [],
            "fix": [],
            "sem": [],
            "bench": "Run Oracle validation.",
        }

        self.assertEqual(
            PipelineManager._validate_json_contract(tuner_payload, tuner_schema),
            [],
        )
        self.assertEqual(
            PipelineManager._validate_json_contract(critic_payload, critic_schema),
            [],
        )

        critic_payload["sum"] = "x" * 401
        critic_payload["block"] = ["issue"] * 5
        errors = PipelineManager._validate_json_contract(critic_payload, critic_schema)
        self.assertTrue(any("longer than 400" in error for error in errors))
        self.assertTrue(any("more than 4" in error for error in errors))

    def test_response_contracts_fail_closed(self) -> None:
        tuner_schema = self.load_json("contracts/tuner_response.schema.json")
        errors = PipelineManager._validate_json_contract(
            {"sql": "SELECT 1 FROM dual", "why": [], "risk": []},
            tuner_schema,
        )
        self.assertTrue(errors)

    def test_db_examples_match_contracts(self) -> None:
        catalog_schema = self.load_json("contracts/db_catalog.schema.json")
        query_schema = self.load_json("contracts/query_context.schema.json")
        catalog = self.load_json("db_context/catalog.example.json")
        oracle_template = self.load_json("contracts/oracle_db_metadata.template.json")
        query = self.load_json("db_context/query_context.example.json")

        self.assertEqual(
            PipelineManager._validate_json_contract(catalog, catalog_schema),
            [],
        )
        self.assertEqual(
            PipelineManager._validate_json_contract(query, query_schema),
            [],
        )
        self.assertEqual(
            PipelineManager._validate_json_contract(oracle_template, catalog_schema),
            [],
        )

    def test_oracle_launchers_select_retune_and_ui_modes(self) -> None:
        run_oracle = (AUTORUN_DIR / "run_oracle.sh").read_text(encoding="utf-8")
        without = (AUTORUN_DIR / "Without_run_oracle.sh").read_text(encoding="utf-8")
        with_ui = (AUTORUN_DIR / "Without_run_oracle_withUi.sh").read_text(
            encoding="utf-8"
        )
        common = (AUTORUN_DIR / "_run_oracle_pipeline.sh").read_text(encoding="utf-8")

        self.assertIn('${CRITIC_RETUNE_ROUNDS:-1}', run_oracle)
        self.assertIn('"${SCRIPT_DIR}/_run_oracle_pipeline.sh" 0 without-ui', without)
        self.assertIn('"${SCRIPT_DIR}/_run_oracle_pipeline.sh" 0 with-ui', with_ui)
        self.assertIn('--critic-retune-rounds "${critic_retune_rounds}"', common)
        self.assertIn("TUNER_STRUCTURED_OUTPUT=1", common)
        self.assertIn("Qwen/WithoutUI/start.sh", common)
        self.assertIn("DeepSeek_V4_Flash_0731_DSpark", common)
        self.assertIn('DEEPSEEK_START="${DEEPSEEK_DIR}/WithoutUI/start.sh"', common)
        self.assertIn('CRITIC_MODELS="${CRITIC_MODELS-hy3}"', common)
        self.assertIn("FINAL_WRITER_START_SCRIPT", common)
        self.assertIn("start_qwen_ui_offline.sh", common)

        offline_ui = (AUTORUN_DIR / "start_qwen_ui_offline.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("up -d --no-build --pull never", offline_ui)
        self.assertNotIn("up -d --build", offline_ui)

    def test_final_launchers_are_self_contained_and_offline_bounded(self) -> None:
        run_files = (AUTORUN_DIR / "run_files.sh").read_text(encoding="utf-8")
        oracle_common = (AUTORUN_DIR / "_run_oracle_pipeline.sh").read_text(
            encoding="utf-8"
        )

        for launcher in (run_files, oracle_common):
            self.assertIn('"${SCRIPT_DIR}/main.py"', launcher)
            self.assertNotIn("AutorunEnum/main.py", launcher)
            self.assertIn(
                'TUNER_THINKING="${TUNER_THINKING-1}"',
                launcher,
            )
            self.assertIn(
                'TUNER_MAX_TOKENS="${TUNER_MAX_TOKENS-81920}"',
                launcher,
            )
            self.assertIn(
                'FINAL_WRITER_REASONING_EFFORT="${FINAL_WRITER_REASONING_EFFORT-max}"',
                launcher,
            )
            self.assertIn(
                'FINAL_WRITER_AGENT_MODE="${FINAL_WRITER_AGENT_MODE-minimal}"',
                launcher,
            )

        self.assertIn(
            'DEEPSEEK_DIR="${REPO_ROOT}/Llamacpp/DeepSeek_V4_Flash_0731_DSpark"',
            run_files,
        )
        self.assertIn('DEEPSEEK_START="${DEEPSEEK_DIR}/WithoutUI/start.sh"', run_files)
        self.assertIn(
            'FINAL_WRITER_MODEL_NAME="${FINAL_WRITER_MODEL_NAME-deepseek-v4-flash}"',
            run_files,
        )
        self.assertIn(
            'FINAL_WRITER_REQUEST_STYLE="${FINAL_WRITER_REQUEST_STYLE-ds4}"',
            run_files,
        )
        self.assertIn(
            'FINAL_WRITER_CONTEXT_SIZE="${FINAL_WRITER_CONTEXT_SIZE-32768}"',
            run_files,
        )
        self.assertIn(
            'FINAL_WRITER_TEMPERATURE="${FINAL_WRITER_TEMPERATURE-0}"',
            run_files,
        )
        self.assertIn(
            'FINAL_WRITER_STRUCTURED_OUTPUT="${FINAL_WRITER_STRUCTURED_OUTPUT-0}"',
            run_files,
        )
        self.assertIn(
            'FINAL_WRITER_MODEL_NAME="${FINAL_WRITER_MODEL_NAME-deepseek-v4-flash}"',
            oracle_common,
        )
        self.assertIn(
            'FINAL_WRITER_CONTEXT_SIZE="${FINAL_WRITER_CONTEXT_SIZE-32768}"',
            oracle_common,
        )

    def test_file_launcher_falls_back_when_oracle_is_unavailable(self) -> None:
        run_files = (AUTORUN_DIR / "run_files.sh").read_text(encoding="utf-8")

        self.assertNotIn('${1,,}', run_files)
        self.assertIn('ORACLE_VALIDATE="${ORACLE_VALIDATE-1}"', run_files)
        self.assertIn(
            'REQUIRE_ORACLE_VALIDATION="${REQUIRE_ORACLE_VALIDATION-0}"',
            run_files,
        )
        self.assertIn('EXECUTE_BENCHMARK="${EXECUTE_BENCHMARK-0}"', run_files)
        self.assertIn("ARGS+=(--oracle-validate)", run_files)
        self.assertIn("ARGS+=(--execute-benchmark)", run_files)
        self.assertIn("import oracledb", run_files)
        self.assertIn("oracle_preflight.py", run_files)
        self.assertIn("continuing with model-only processing", run_files)

    def test_deepseek_0731_with_ui_has_reproducible_build_and_health_paths(self) -> None:
        with_ui = REPO_ROOT / "Llamacpp/DeepSeek_V4_Flash_0731/WithUI"
        compose = (with_ui / "docker-compose.yml").read_text(encoding="utf-8")
        build = (with_ui / "build.sh").read_text(encoding="utf-8")
        start = (with_ui / "start.sh").read_text(encoding="utf-8")
        health = (with_ui / "health_check.sh").read_text(encoding="utf-8")

        self.assertIn("dockerfile: docker/Dockerfile", compose)
        self.assertIn("pull_policy: never", compose)
        self.assertIn("llm-sql-open-webui:v0.9.4-dgx-stats", compose)
        self.assertIn("condition: service_healthy", compose)
        self.assertIn("TEMPERATURE: ${TEMPERATURE:-1.0}", compose)
        self.assertIn("TOP_P: ${TOP_P:-0.95}", compose)
        self.assertIn("REASONING_EFFORT: ${REASONING_EFFORT:-max}", compose)
        self.assertIn(
            "LLAMA_SERVER_EXTRA_ARGS: ${LLAMA_SERVER_EXTRA_ARGS:---metrics --perf --jinja}",
            compose,
        )
        self.assertIn("build deepseek-iq3-xxs", build)
        self.assertIn("host_compose.sh", start)
        self.assertIn("/v1/models", health)
        self.assertIn("OPEN_WEBUI_PORT", health)

        server = (
            REPO_ROOT / "Llamacpp/DeepSeek_V4_Flash_0731/scripts/03_start_server.sh"
        ).read_text(encoding="utf-8")
        config = (
            REPO_ROOT / "Llamacpp/DeepSeek_V4_Flash_0731/config.env.example"
        ).read_text(encoding="utf-8")
        self.assertIn('--chat-template-kwargs "${template_kwargs}"', server)
        self.assertIn("REASONING_EFFORT=max", config)
        self.assertIn("TEMPERATURE=1.0", config)
        self.assertIn("TOP_P=0.95", config)

        self.assertTrue(
            (REPO_ROOT / "Llamacpp/DeepSeek_V4_Flash_0731/docker/Dockerfile").is_file()
        )
        host_compose = (
            REPO_ROOT / "Llamacpp/DeepSeek_V4_Flash_0731/scripts/host_compose.sh"
        ).read_text(encoding="utf-8")
        self.assertIn("up -d --no-build --pull never", host_compose)
        self.assertIn("iq3xxs_wait_for_health", host_compose)

    def test_ds4_dspark_without_ui_contract(self) -> None:
        model_dir = REPO_ROOT / "Llamacpp/DeepSeek_V4_Flash_0731_DSpark"
        without_ui = model_dir / "WithoutUI"
        with_ui = model_dir / "WithUI"
        compose = (without_ui / "docker-compose.yml").read_text(encoding="utf-8")
        start = (without_ui / "start.sh").read_text(encoding="utf-8")
        with_ui_start = (with_ui / "start.sh").read_text(encoding="utf-8")
        offline_proxy = (REPO_ROOT / "Llamacpp/offline_proxy.sh").read_text(
            encoding="utf-8"
        )
        runtime = (model_dir / "runtime.env").read_text(encoding="utf-8")
        entrypoint = (model_dir / "scripts/entrypoint.sh").read_text(encoding="utf-8")
        pin_file = model_dir / "vendor/ds4-src/.pinned-commit"
        prepare_online = (model_dir / "prepare_online.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn("DeepSeek-V4-Flash-DSpark-support-0731.gguf", runtime)
        self.assertIn("b7e9f0091139999b6c070a57590c447c5741da5c", runtime)
        if pin_file.is_file():
            self.assertEqual(
                pin_file.read_text(encoding="utf-8").strip(),
                "b7e9f0091139999b6c070a57590c447c5741da5c",
            )
        else:
            # The public repository intentionally excludes vendored DS4 source.
            # prepare_online.sh must create the same revision marker before build.
            self.assertIn(
                "printf '%s\\n' \"${DS4_COMMIT}\" > "
                '"${archive_dir}/source/.pinned-commit"',
                prepare_online,
            )
        self.assertIn("ds4/archive/${DS4_COMMIT}.tar.gz", prepare_online)
        self.assertNotIn("DEFAULT_TEMPERATURE=", runtime)
        self.assertIn("DS4_WRAPPER_REVISION=20260807.3", runtime)
        self.assertIn("QUALITY_MODE=0", runtime)
        self.assertNotIn('${1,,}', entrypoint)
        self.assertIn('DSPARK_SUPPORT_GGUF_FILE: ${DSPARK_SUPPORT_GGUF_FILE}', compose)
        self.assertNotIn("open-webui", compose)
        self.assertIn("up -d --no-build --pull never", start)
        self.assertIn('--mtp "${DSPARK_SUPPORT_PATH}"', entrypoint)
        self.assertIn("--dspark", entrypoint)
        self.assertIn('--gpu-vram "${GPU_VRAM}"', entrypoint)
        self.assertIn('--prefill-chunk "${PREFILL_CHUNK}"', entrypoint)
        self.assertIn("--ssd-streaming", entrypoint)
        self.assertIn(
            '--ssd-streaming-cache-experts "${SSD_STREAMING_CACHE_EXPERTS}"',
            entrypoint,
        )
        self.assertIn(
            "DS4_ENABLE_DSPARK=0",
            (model_dir / "config.env.example").read_text(encoding="utf-8"),
        )
        self.assertNotIn("--no-mtp", entrypoint)
        self.assertIn('"${PORT:-8080}" ds4-api', with_ui_start)
        self.assertIn('"${OPEN_WEBUI_PORT:-3000}" ds4-webui', with_ui_start)
        self.assertIn("stop_all_proxies", offline_proxy)
        self.assertIn("[name]", offline_proxy)

        modelctl = (REPO_ROOT / "Llamacpp/modelctl.sh").read_text(encoding="utf-8")
        self.assertIn("DeepSeek_V4_Flash_0731_DSpark/WithoutUI/stop.sh", modelctl)
        self.assertIn("DeepSeek_V4_Flash_0731/WithoutUI/stop.sh", modelctl)

    def test_oracle_preflight_and_explicit_env_contract(self) -> None:
        preflight = (AUTORUN_DIR / "oracle_preflight.py").read_text(encoding="utf-8")
        manager = (AUTORUN_DIR / "PipelineManager.py").read_text(encoding="utf-8")

        self.assertIn("AUTORUN_ENV_FILE", preflight)
        self.assertIn("SELECT 1 FROM dual", preflight)
        self.assertIn("SELECT 1 FROM v$sql", preflight)
        self.assertIn("DBMS_XPLAN.DISPLAY", preflight)
        self.assertIn("AUTORUN_ENV_FILE", manager)
        self.assertIn("connection.call_timeout = self.oracle_call_timeout_ms", manager)

    def test_launchers_use_one_selected_virtualenv_python(self) -> None:
        runtime = (AUTORUN_DIR / "_python_runtime.sh").read_text(encoding="utf-8")
        run_files = (AUTORUN_DIR / "run_files.sh").read_text(encoding="utf-8")
        oracle = (AUTORUN_DIR / "_run_oracle_pipeline.sh").read_text(
            encoding="utf-8"
        )

        self.assertIn('VIRTUAL_ENV:-', runtime)
        self.assertIn('${repo_root}/.venv/bin/python3', runtime)
        self.assertIn("Do not run the whole pipeline with sudo", runtime)
        for launcher in (run_files, oracle):
            self.assertIn('source "${SCRIPT_DIR}/_python_runtime.sh"', launcher)
            self.assertIn('"${AUTORUN_PYTHON}" "${ARGS[@]}"', launcher)
            self.assertNotIn('python3 "${ARGS[@]}"', launcher)

        with tempfile.TemporaryDirectory() as temp_dir:
            venv_bin = Path(temp_dir) / "bin"
            venv_bin.mkdir()
            (venv_bin / "python3").symlink_to(Path(sys.executable))
            command = (
                f'source "{AUTORUN_DIR / "_python_runtime.sh"}"; '
                f'VIRTUAL_ENV="{temp_dir}"; unset PYTHON_BIN; '
                f'autorun_resolve_python "{REPO_ROOT}" "{AUTORUN_DIR}"; '
                'printf "%s" "${AUTORUN_PYTHON}"'
            )
            result = subprocess.run(
                ["bash", "-c", command],
                check=True,
                capture_output=True,
                text=True,
                env=dict(os.environ),
            )
            self.assertTrue(result.stdout.rstrip().endswith("/bin/python3"))

    def test_model_launchers_do_not_build_or_pull_in_offline_mode(self) -> None:
        launchers = (
            REPO_ROOT / "Llamacpp/Qwen/WithoutUI/start.sh",
            REPO_ROOT / "Llamacpp/DeepSeek_V4_Flash_0731/WithoutUI/start.sh",
            REPO_ROOT / "Llamacpp/DeepSeek_V4_Flash_0731_DSpark/WithoutUI/start.sh",
            REPO_ROOT / "Llamacpp/Hy3/Reasoning-start.sh",
        )
        compose_files = (
            REPO_ROOT / "Llamacpp/Qwen/WithoutUI/docker-compose.yml",
            REPO_ROOT
            / "Llamacpp/DeepSeek_V4_Flash_0731/WithoutUI/docker-compose.yml",
            REPO_ROOT
            / "Llamacpp/DeepSeek_V4_Flash_0731_DSpark/WithoutUI/docker-compose.yml",
            REPO_ROOT / "Llamacpp/Hy3/Reasoning-docker-compose.yml",
        )

        for launcher in launchers:
            content = launcher.read_text(encoding="utf-8")
            if "host_compose.sh" in content:
                content += (
                    REPO_ROOT
                    / "Llamacpp/DeepSeek_V4_Flash_0731/scripts/host_compose.sh"
                ).read_text(encoding="utf-8")
            self.assertIn("up -d --no-build --pull never", content)
            self.assertNotIn("up -d --build", content)

        for compose_file in compose_files:
            content = compose_file.read_text(encoding="utf-8")
            self.assertIn("pull_policy: never", content)

    def test_db_object_selection_keeps_owner_and_dependencies(self) -> None:
        objects = [
            {
                "owner": "APP",
                "name": "ORDERS_V",
                "object_type": "VIEW",
                "dependencies": ["APP.ORDERS"],
            },
            {
                "owner": "APP",
                "name": "ORDERS",
                "object_type": "TABLE",
                "dependencies": [],
            },
        ]
        selected, unresolved = PipelineManager._select_relevant_db_objects(
            objects,
            ["APP.ORDERS_V"],
        )

        self.assertEqual([item["name"] for item in selected], ["ORDERS_V", "ORDERS"])
        self.assertEqual(unresolved, [])
        self.assertEqual(
            PipelineManager.extract_tables("SELECT * FROM APP.ORDERS"),
            ["APP.ORDERS"],
        )

    def test_materialization_policy_checks(self) -> None:
        self.assertTrue(
            PipelineManager._prohibited_sql_features(
                "SELECT /*+ MATERIALIZE */ * FROM APP.ORDERS"
            )
        )
        self.assertTrue(
            PipelineManager._prohibited_sql_features(
                "SELECT /*+ RESULT_CACHE */ * FROM APP.ORDERS"
            )
        )
        self.assertEqual(
            PipelineManager._forbidden_plan_operations(
                ["| TEMP TABLE TRANSFORMATION |", "| LOAD AS SELECT |"]
            ),
            ["TEMP TABLE TRANSFORMATION", "LOAD AS SELECT"],
        )

    def test_sql_safety_policy_rejects_multiple_statements_and_packages(self) -> None:
        self.assertTrue(
            PipelineManager._sql_safety_violations(
                "SELECT 1 FROM dual; SELECT 2 FROM dual"
            )
        )
        self.assertTrue(
            PipelineManager._sql_safety_violations(
                "SELECT UTL_HTTP.REQUEST('https://example.invalid') FROM dual"
            )
        )
        self.assertEqual(
            PipelineManager._sql_safety_violations("SELECT 1 FROM dual"),
            [],
        )
        self.assertEqual(
            PipelineManager._sql_safety_violations(
                "SELECT '12:30; safe text' FROM dual"
            ),
            [],
        )

    def test_execution_binds_fail_closed_and_preserve_values(self) -> None:
        manager = object.__new__(PipelineManager)
        manager._load_db_context = lambda job: {
            "query": {"binds": [{"name": "station_id", "value": "4311390"}]}
        }
        job = SimpleNamespace(name="bind_test")
        sql = "SELECT * FROM station WHERE station_id = :station_id"
        self.assertEqual(
            manager._execution_binds(job, sql, sql),
            {"station_id": "4311390"},
        )
        self.assertEqual(
            manager._execution_binds(
                job, "SELECT ':not_a_bind' FROM dual", "SELECT ':not_a_bind' FROM dual"
            ),
            {},
        )
        with self.assertRaisesRegex(RuntimeError, "bind names differ"):
            manager._execution_binds(job, sql, "SELECT * FROM station WHERE station_id = :id")
        manager._load_db_context = lambda job: {"query": {"binds": []}}
        with self.assertRaisesRegex(RuntimeError, "missing execution bind values"):
            manager._execution_binds(job, sql, sql)

    def test_critic_omits_duplicate_sql_from_model_context(self) -> None:
        original = "SELECT 1 FROM dual"
        local_draft = "-- local draft\nSELECT 1 FROM dual;\n"
        payload, is_duplicate = PipelineManager._critic_tuned_sql_payload(
            original,
            local_draft,
        )
        self.assertTrue(is_duplicate)
        self.assertIn("UNCHANGED", payload)
        self.assertNotIn("SELECT 1", payload)

        rewritten = "SELECT /* rewritten */ 2 FROM dual"
        payload, is_duplicate = PipelineManager._critic_tuned_sql_payload(
            original,
            rewritten,
        )
        self.assertFalse(is_duplicate)
        self.assertEqual(payload, rewritten)

    def test_sample_comparison_fails_when_validation_is_truncated(self) -> None:
        class Cursor:
            description = [("ID",)]

            def execute(self, sql, binds):
                self.binds = binds

            def fetchall(self):
                return [(1,), (2,)]

        manager = object.__new__(PipelineManager)
        manager.validation_row_limit = 1
        manager._execution_binds = lambda job, original, tuned: {}
        result = manager._compare_sql_samples(
            Cursor(), SimpleNamespace(), "SELECT 1 FROM dual", "SELECT 1 FROM dual"
        )
        self.assertFalse(result["passed"])
        self.assertFalse(result["checks"]["complete_results"])

    def test_empty_collection_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "source"
            source.mkdir()
            manager = PipelineManager(
                workspace=root / "workspace",
                source_dir=source,
                mode="files",
                tuner="local",
            )
            with self.assertRaisesRegex(RuntimeError, "No SQL statements were collected"):
                manager.collect_sql()

    def test_file_collection_supports_recursive_multiple_sources(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source_a = root / "Query"
            source_b = root / "ManualExtra"
            nested = source_a / "test-five"
            nested.mkdir(parents=True)
            source_b.mkdir()
            (source_a / "root.sql").write_text("SELECT 1 FROM dual", encoding="utf-8")
            (nested / "nested.sql").write_text("SELECT 2 FROM dual", encoding="utf-8")
            (source_b / "extra.sql").write_text("SELECT 3 FROM dual", encoding="utf-8")

            manager = PipelineManager(
                workspace=root / "workspace",
                source_dir=[source_a, source_b],
                mode="files",
                tuner="local",
            )
            manager.collect_sql()

            self.assertEqual(len(manager.jobs), 3)
            self.assertEqual(
                {job.source_path.name for job in manager.jobs},
                {"root.sql", "nested.sql", "extra.sql"},
            )
            self.assertTrue(
                all(job.metrics["source_directory"] for job in manager.jobs)
            )

    def test_previous_workspace_is_archived_before_new_run(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "source"
            source.mkdir()
            manager = PipelineManager(
                workspace=root / "workspace",
                source_dir=source,
                mode="files",
                tuner="local",
            )
            stale = manager.critique_dir / "old" / "deepseek.json"
            stale.parent.mkdir(parents=True)
            stale.write_text("{}", encoding="utf-8")
            (manager.workspace / "summary.json").write_text("{}", encoding="utf-8")

            manager._prepare_run_workspace()

            archives = list(manager.archive_dir.glob("run-*"))
            self.assertEqual(len(archives), 1)
            self.assertTrue((archives[0] / "critique" / "old" / "deepseek.json").exists())
            self.assertTrue((archives[0] / "summary.json").exists())
            self.assertEqual(list(manager.critique_dir.iterdir()), [])

    def test_final_verification_requires_explicit_gate_approval(self) -> None:
        manager = object.__new__(PipelineManager)
        manager.require_critic_approval = True
        manager.require_oracle_validation = True
        job = SimpleNamespace(benchmark={"improved": True})

        self.assertFalse(manager._job_passed_final_verification(job))
        job.benchmark["critic_approved"] = True
        self.assertFalse(manager._job_passed_final_verification(job))
        job.benchmark["oracle_validation_passed"] = True
        self.assertTrue(manager._job_passed_final_verification(job))

    def test_partial_batch_keeps_verified_job(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "source"
            source.mkdir()
            manager = PipelineManager(
                workspace=root / "workspace",
                source_dir=source,
                mode="files",
                tuner="local",
            )
            manager.require_critic_approval = False
            manager.require_oracle_validation = False
            manager.execute_benchmark = True

            jobs = []
            for name, improved in (("passed", True), ("rejected", False)):
                source_path = source / f"{name}.sql"
                source_path.write_text("SELECT 1 FROM dual\n", encoding="utf-8")
                tuned_path = manager.tuning_dir / f"{name}-B.sql"
                tuned_path.write_text("SELECT 1 FROM dual\n", encoding="utf-8")
                job = QueryJob(name=name, source_path=source_path, input_path=source_path)
                job.tuned_path = tuned_path
                job.benchmark = {"improved": improved}
                jobs.append(job)

            manager.jobs = jobs
            manager.move_failed()

            self.assertEqual(jobs[0].status, QueryStatus.SUCCESS)
            self.assertEqual(jobs[1].status, QueryStatus.FAILED)
            self.assertTrue((manager.improved_dir / "passed-B.sql").exists())
            self.assertTrue((manager.failed_dir / "rejected-B.sql").exists())
            summary = json.loads((manager.workspace / "summary.json").read_text())
            self.assertEqual(summary["result"], "PARTIAL")

    def test_pipeline_retunes_once_after_critic_feedback(self) -> None:
        class FakeManager:
            max_retry = 0
            critic_retune_rounds = 1

            def __init__(self):
                self.calls = []

            def should_retune_after_critique(self, completed_rounds):
                return completed_rounds < self.critic_retune_rounds

            def __getattr__(self, name):
                if name == "is_improved":
                    return lambda: True
                if name == "prepare_critic_retune":
                    return lambda round_number: self.calls.append(
                        f"prepare_critic_retune:{round_number}"
                    )
                return lambda: self.calls.append(name)

        manager = FakeManager()
        run_pipeline(manager)

        self.assertEqual(manager.calls.count("tune_sql"), 2)
        self.assertEqual(manager.calls.count("critique_tuned_sql"), 2)
        self.assertIn("prepare_critic_retune:1", manager.calls)
        tune_indexes = [
            index for index, call in enumerate(manager.calls) if call == "tune_sql"
        ]
        critic_indexes = [
            index
            for index, call in enumerate(manager.calls)
            if call == "critique_tuned_sql"
        ]
        critic_index = critic_indexes[0]
        prepare_index = manager.calls.index("prepare_critic_retune:1")
        validate_index = manager.calls.index("validate_oracle")
        self.assertLess(tune_indexes[0], critic_index)
        self.assertLess(critic_index, prepare_index)
        self.assertLess(prepare_index, tune_indexes[1])
        self.assertLess(tune_indexes[1], critic_indexes[1])
        self.assertLess(critic_indexes[1], validate_index)

    def test_missing_model_endpoint_fails_closed(self) -> None:
        self.assertFalse(
            PipelineManager._model_endpoint_ready(
                "http://127.0.0.1:1/v1", "qwen-sql-tuner"
            )
        )

    def test_feedback_rewrite_uses_deepseek_and_previous_qwen_candidate(self) -> None:
        class Response:
            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, traceback):
                return False

            def read(self):
                return json.dumps(
                    {
                        "choices": [
                            {
                                "message": {
                                    "content": json.dumps(
                                        {
                                            "sql": "SELECT 3 FROM dual",
                                            "why": [],
                                            "risk": [],
                                            "check": [],
                                        }
                                    )
                                }
                            }
                        ]
                    }
                ).encode()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "source.sql"
            source.write_text("SELECT 1 FROM dual", encoding="utf-8")
            manager = PipelineManager(
                workspace=root / "workspace",
                source_dir=source,
                mode="files",
                tuner="llm",
            )
            job = QueryJob(name="retune", source_path=source, input_path=source)
            job.tuned_path = manager.tuning_dir / "retune-B.sql"
            job.tuned_path.write_text("SELECT 2 FROM dual", encoding="utf-8")
            (manager.analysis_dir / "retune.json").write_text("{}", encoding="utf-8")
            (manager.feedback_dir / "retune.json").write_text(
                json.dumps({"name": "retune", "critics": [{"fix": ["review"]}]}),
                encoding="utf-8",
            )
            manager._load_db_context = lambda unused_job: {}
            manager.tuning_round = 2

            writer_profile = {
                "FINAL_WRITER_MODEL_NAME": "deepseek-v4-flash",
                "FINAL_WRITER_REQUEST_STYLE": "ds4",
                "FINAL_WRITER_TEMPERATURE": "0",
                "FINAL_WRITER_TOP_P": "1.0",
                "FINAL_WRITER_TOP_K": "0",
                "FINAL_WRITER_MIN_P": "0.0",
                "FINAL_WRITER_PRESENCE_PENALTY": "0.0",
                "FINAL_WRITER_FREQUENCY_PENALTY": "0.0",
                "FINAL_WRITER_REPETITION_PENALTY": "1.0",
                "FINAL_WRITER_SEED": "42",
                "FINAL_WRITER_THINKING_MODE": "thinking",
                "FINAL_WRITER_REASONING_EFFORT": "max",
                "FINAL_WRITER_AGENT_MODE": "minimal",
                "FINAL_WRITER_MAX_TOKENS": "16384",
                "FINAL_WRITER_CONTEXT_SIZE": "65536",
                "FINAL_WRITER_CACHE_PROMPT": "1",
                "FINAL_WRITER_STRUCTURED_OUTPUT": "0",
            }
            with patch.dict("os.environ", writer_profile, clear=False):
                with patch("urllib.request.urlopen", return_value=Response()) as mocked:
                    manager._tune_with_llm(job, source.read_text(encoding="utf-8"))

            request_payload = json.loads(mocked.call_args.args[0].data.decode())
            tuning_input = json.loads(request_payload["messages"][1]["content"])
            self.assertEqual(request_payload["model"], "deepseek-v4-flash")
            self.assertEqual(request_payload["temperature"], 0.0)
            self.assertEqual(request_payload["top_p"], 1.0)
            self.assertEqual(request_payload["top_k"], 0)
            self.assertEqual(request_payload["min_p"], 0.0)
            self.assertEqual(request_payload["presence_penalty"], 0.0)
            self.assertEqual(request_payload["frequency_penalty"], 0.0)
            self.assertEqual(request_payload["repeat_penalty"], 1.0)
            self.assertEqual(request_payload["seed"], 42)
            self.assertEqual(request_payload["max_tokens"], 16384)
            self.assertTrue(request_payload["cache_prompt"])
            self.assertNotIn("reasoning_format", request_payload)
            self.assertTrue(request_payload["think"])
            self.assertEqual(request_payload["reasoning_effort"], "max")
            self.assertNotIn("chat_template_kwargs", request_payload)
            self.assertNotIn("response_format", request_payload)
            self.assertIn(
                "minimal single-turn code agent",
                request_payload["messages"][0]["content"],
            )
            self.assertEqual(tuning_input["original_sql"], "SELECT 1 FROM dual")
            self.assertEqual(tuning_input["sql"], "SELECT 2 FROM dual")
            self.assertNotIn("previous_tuned_sql", tuning_input)
            self.assertTrue(tuning_input["critic_feedback"]["critics"])

    def test_failed_deepseek_rewrite_preserves_qwen_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "source.sql"
            source.write_text("SELECT 1 FROM dual", encoding="utf-8")
            manager = PipelineManager(
                workspace=root / "workspace",
                source_dir=source,
                mode="files",
                tuner="llm",
            )
            try:
                job = QueryJob(name="preserve", source_path=source, input_path=source)
                job.tuned_path = manager.tuning_dir / "preserve-B.sql"
                job.tuned_path.write_text("SELECT 2 FROM dual", encoding="utf-8")
                manager.jobs = [job]
                manager.tuning_round = 1
                manager._ensure_model_endpoint = lambda *args: None
                manager._tune_with_llm = lambda *args: (_ for _ in ()).throw(
                    TimeoutError("deepseek unavailable")
                )

                with patch.dict(
                    "os.environ",
                    {"FINAL_WRITER_HEARTBEAT_SEC": "0"},
                    clear=False,
                ):
                    manager.tune_sql()

                self.assertEqual(
                    job.tuned_path.read_text(encoding="utf-8").strip(),
                    "SELECT 2 FROM dual",
                )
                report = json.loads(
                    (manager.tuning_dir / "preserve-B.json").read_text(encoding="utf-8")
                )
                self.assertEqual(report["writer_role"], "writer:deepseek")
                self.assertIn("deepseek unavailable", job.error)
            finally:
                manager.close()

    def test_critic_sampling_and_reasoning_profiles(self) -> None:
        class Response:
            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, traceback):
                return False

            def read(self):
                return json.dumps(
                    {
                        "choices": [
                            {
                                "message": {
                                    "content": json.dumps(
                                        {
                                            "ok": True,
                                            "risk": "low",
                                            "sum": "Safe to validate.",
                                            "block": [],
                                            "fix": [],
                                            "sem": [],
                                            "bench": "Run Oracle validation.",
                                        }
                                    )
                                }
                            }
                        ]
                    }
                ).encode()

        profiles = [
            (
                "deepseek",
                {
                    "CRITIC_DEEPSEEK_REQUEST_STYLE": "deepseek_v4",
                    "CRITIC_DEEPSEEK_TEMPERATURE": "1.0",
                    "CRITIC_DEEPSEEK_TOP_P": "0.95",
                    "CRITIC_DEEPSEEK_TOP_K": "0",
                    "CRITIC_DEEPSEEK_MIN_P": "0.0",
                    "CRITIC_DEEPSEEK_PRESENCE_PENALTY": "0.0",
                    "CRITIC_DEEPSEEK_FREQUENCY_PENALTY": "0.0",
                    "CRITIC_DEEPSEEK_REPETITION_PENALTY": "1.0",
                    "CRITIC_DEEPSEEK_SEED": "42",
                    "CRITIC_DEEPSEEK_THINKING_MODE": "thinking",
                    "CRITIC_DEEPSEEK_REASONING_EFFORT": "max",
                },
                1.0,
                0.95,
                {"thinking_mode": "thinking", "reasoning_effort": "max"},
            ),
            (
                "hy3",
                {
                    "CRITIC_HY3_REQUEST_STYLE": "hy3",
                    "CRITIC_HY3_TEMPERATURE": "0.9",
                    "CRITIC_HY3_TOP_P": "1.0",
                    "CRITIC_HY3_TOP_K": "0",
                    "CRITIC_HY3_MIN_P": "0.0",
                    "CRITIC_HY3_PRESENCE_PENALTY": "0.0",
                    "CRITIC_HY3_FREQUENCY_PENALTY": "0.0",
                    "CRITIC_HY3_REPETITION_PENALTY": "1.0",
                    "CRITIC_HY3_SEED": "42",
                    "CRITIC_HY3_REASONING_EFFORT": "high",
                },
                0.9,
                1.0,
                {"reasoning_effort": "high"},
            ),
        ]

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "source.sql"
            source.write_text("SELECT 1 FROM dual", encoding="utf-8")
            manager = PipelineManager(
                workspace=root / "workspace",
                source_dir=source,
                mode="files",
                tuner="local",
            )
            manager._load_db_context = lambda unused_job: {}
            job = QueryJob(name="sampling", source_path=source, input_path=source)

            for critic, environment, temperature, top_p, template_kwargs in profiles:
                with self.subTest(critic=critic):
                    with patch.dict("os.environ", environment, clear=False):
                        with patch(
                            "urllib.request.urlopen", return_value=Response()
                        ) as mocked:
                            manager._call_critic_model(
                                job,
                                critic,
                                "SELECT 1 FROM dual",
                                "SELECT 1 FROM dual",
                            )

                    request_payload = json.loads(mocked.call_args.args[0].data.decode())
                    self.assertEqual(request_payload["temperature"], temperature)
                    self.assertEqual(request_payload["top_p"], top_p)
                    self.assertEqual(request_payload["top_k"], 0)
                    self.assertEqual(request_payload["min_p"], 0.0)
                    self.assertEqual(request_payload["presence_penalty"], 0.0)
                    self.assertEqual(request_payload["frequency_penalty"], 0.0)
                    self.assertEqual(request_payload["repeat_penalty"], 1.0)
                    self.assertEqual(request_payload["seed"], 42)
                    self.assertEqual(
                        request_payload["chat_template_kwargs"], template_kwargs
                    )

    def test_ordered_query_rejects_reordered_result(self) -> None:
        manager = object.__new__(PipelineManager)
        manager._execution_binds = lambda job, original, tuned: {}
        samples = iter(
            [
                {
                    "columns": ["ID"],
                    "row_count": 2,
                    "complete": True,
                    "ordered_hash": "ascending",
                    "unordered_hash": "same-set",
                    "sample_rows": [],
                    "elapsed_ms": 1,
                },
                {
                    "columns": ["ID"],
                    "row_count": 2,
                    "complete": True,
                    "ordered_hash": "descending",
                    "unordered_hash": "same-set",
                    "sample_rows": [],
                    "elapsed_ms": 1,
                },
            ]
        )
        manager._sample_select = lambda cursor, sql, binds: next(samples)

        result = manager._compare_sql_samples(
            None,
            SimpleNamespace(),
            "SELECT id FROM app.items ORDER BY id",
            "SELECT id FROM app.items ORDER BY id DESC",
        )

        self.assertFalse(result["passed"])
        self.assertTrue(result["checks"]["order_preservation_required"])
        self.assertFalse(result["checks"]["ordered_hash_match"])

    def test_sql_comment_stripping_preserves_literal_text(self) -> None:
        sql = "SELECT '/*not a comment*/', '--still data' FROM dual -- real comment"
        stripped = PipelineManager._strip_sql_comments(sql)
        self.assertIn("'/*not a comment*/'", stripped)
        self.assertIn("'--still data'", stripped)
        self.assertNotIn("real comment", stripped)

    def test_unbenchmarked_result_can_pass_explicit_review_gates(self) -> None:
        manager = object.__new__(PipelineManager)
        manager.execute_benchmark = False
        manager.require_critic_approval = True
        manager.require_oracle_validation = False
        job = SimpleNamespace(
            error=None,
            benchmark={"critic_approved": True, "improved": None},
        )
        self.assertTrue(manager._job_passed_final_verification(job))

    def test_workspace_lock_prevents_concurrent_runs(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "source"
            source.mkdir()
            first = PipelineManager(
                workspace=root / "workspace",
                source_dir=source,
                mode="files",
                tuner="local",
            )
            try:
                with self.assertRaisesRegex(RuntimeError, "another AutorunEnum process"):
                    PipelineManager(
                        workspace=root / "workspace",
                        source_dir=source,
                        mode="files",
                        tuner="local",
                    )
            finally:
                first.close()

    def test_one_tuner_failure_does_not_abort_remaining_queries(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source_dir = root / "source"
            source_dir.mkdir()
            manager = PipelineManager(
                workspace=root / "workspace",
                source_dir=source_dir,
                mode="files",
                tuner="local",
            )
            try:
                jobs = []
                for index in (1, 2):
                    source = source_dir / f"q{index}.sql"
                    source.write_text(
                        f"SELECT {index} FROM dual", encoding="utf-8"
                    )
                    jobs.append(
                        QueryJob(
                            name=f"q{index}",
                            source_path=source,
                            input_path=source,
                        )
                    )
                manager.jobs = jobs
                manager._should_use_llm = lambda: True
                manager._ensure_model_endpoint = lambda *args: None

                calls = 0

                def tune(job, sql):
                    nonlocal calls
                    calls += 1
                    if calls == 1:
                        raise TimeoutError("simulated timeout")
                    return {"sql": sql, "why": [], "risk": [], "check": []}

                manager._tune_with_llm = tune
                with patch.dict(
                    "os.environ",
                    {"TUNER_HEARTBEAT_SEC": "0"},
                    clear=False,
                ):
                    manager.tune_sql()

                self.assertIn("simulated timeout", jobs[0].error)
                self.assertIsNone(jobs[1].error)
                self.assertTrue(jobs[0].tuned_path.is_file())
                self.assertTrue(jobs[1].tuned_path.is_file())
            finally:
                manager.close()


if __name__ == "__main__":
    unittest.main()
