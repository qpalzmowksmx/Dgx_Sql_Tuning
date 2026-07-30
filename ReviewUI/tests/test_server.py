from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


REVIEW_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REVIEW_DIR))

from server import ReviewData, ReviewDataError  # noqa: E402


class ReviewDataTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.workspace = Path(self.temp_dir.name) / "workspace"
        for name in ("tmp", "A", "B", "critique/job_one", "validation", "benchmark", "feedback", "rag", "archive"):
            (self.workspace / name).mkdir(parents=True, exist_ok=True)

        self.job = {
            "name": "job_one",
            "input_path": str(self.workspace / "tmp" / "job_one.sql"),
            "tuned_path": str(self.workspace / "B" / "job_one-B.sql"),
            "sql_id": "abc123",
            "status": "SUCCESS",
            "tables": ["APP.ORDERS"],
            "retry_count": 0,
            "benchmark": {
                "improved": True,
                "critic_approved": True,
                "oracle_validation_passed": True,
            },
        }
        self._write_json("status.json", [self.job])
        self._write_json(
            "summary.json",
            {"result": "SUCCESS", "mode": "oracle", "tuner": "qwen", "jobs": [self.job]},
        )
        (self.workspace / "tmp" / "job_one.sql").write_text("SELECT * FROM APP.ORDERS\n", encoding="utf-8")
        (self.workspace / "B" / "job_one-B.sql").write_text("SELECT ID FROM APP.ORDERS\n", encoding="utf-8")
        self._write_json(
            "B/job_one-B.json",
            {"llm_result": {"sql": "SELECT ID FROM APP.ORDERS", "why": ["Avoid SELECT star."], "risk": [], "check": ["Compare rows."]}},
        )
        self._write_json(
            "critique/job_one/deepseek.json",
            {
                "critic": "deepseek",
                "approved": True,
                "risk_level": "low",
                "summary": "Safe.",
                "blocking_issues": [],
                "improvement_suggestions": [],
                "semantic_risks": [],
                "benchmark_notes": "Validate.",
            },
        )
        self._write_json("validation/job_one.json", {"passed": True, "failed_stage": None})
        self._write_json("benchmark/job_one.json", {"improved": True, "improvement_pct": 23.4})
        self._write_json("rag/job_one.json", {"db_context": {"objects": [{"name": "ORDERS"}]}})
        self.data = ReviewData(self.workspace)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def _write_json(self, relative: str, payload: object) -> None:
        path = self.workspace / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload), encoding="utf-8")

    def test_lists_current_run_with_counts(self) -> None:
        runs = self.data.list_runs()
        self.assertEqual(len(runs), 1)
        self.assertEqual(runs[0]["id"], ".")
        self.assertEqual(runs[0]["result"], "SUCCESS")
        self.assertEqual(runs[0]["status_counts"], {"SUCCESS": 1})

    def test_builds_human_review_bundle(self) -> None:
        detail = self.data.get_query(".", "job_one")
        self.assertIn("SELECT *", detail["original_sql"])
        self.assertIn("SELECT ID", detail["tuned_sql"])
        self.assertEqual(detail["writer"]["why"], ["Avoid SELECT star."])
        self.assertTrue(detail["critics"]["deepseek"]["ok"])
        self.assertEqual(detail["critics"]["deepseek"]["sum"], "Safe.")
        self.assertIn("approved", detail["raw"]["critics"]["deepseek"])
        self.assertTrue(detail["validation"]["passed"])
        self.assertEqual(detail["db_context"]["objects"][0]["name"], "ORDERS")

    def test_rejects_run_path_traversal(self) -> None:
        with self.assertRaises(ReviewDataError):
            self.data.resolve_run("../../outside")

    def test_rejects_unknown_query_name(self) -> None:
        with self.assertRaises(ReviewDataError):
            self.data.get_query(".", "../summary")

    def test_rejects_malicious_query_name_even_if_status_contains_it(self) -> None:
        malicious = dict(self.job, name="../escape")
        self._write_json("status.json", [malicious])
        with self.assertRaises(ReviewDataError):
            self.data.get_query(".", "../escape")

    def test_does_not_read_artifact_outside_run(self) -> None:
        outside = Path(self.temp_dir.name) / "outside.sql"
        outside.write_text("SELECT secret FROM hidden", encoding="utf-8")
        self.job["input_path"] = str(outside)
        self._write_json("status.json", [self.job])
        detail = self.data.get_query(".", "job_one")
        self.assertNotIn("secret", detail["original_sql"])
        self.assertIn("SELECT *", detail["original_sql"])


if __name__ == "__main__":
    unittest.main()
