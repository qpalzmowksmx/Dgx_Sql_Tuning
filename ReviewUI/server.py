#!/usr/bin/env python3
"""Read-only local review server for AutorunEnum workspace artifacts."""

from __future__ import annotations

import argparse
import json
import mimetypes
import time
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST


APP_DIR = Path(__file__).resolve().parent
STATIC_DIR = APP_DIR / "static"
DEFAULT_WORKSPACE = APP_DIR.parent / "workspace"
MAX_ARTIFACT_BYTES = 5 * 1024 * 1024

# Prometheus metrics
REVIEW_REQUESTS_TOTAL = Counter(
    "review_requests_total",
    "Total number of HTTP requests",
    ["method", "path", "status"]
)
REVIEW_REQUEST_DURATION_SECONDS = Histogram(
    "review_request_duration_seconds",
    "HTTP request duration in seconds",
    ["method", "path"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0)
)


class ReviewDataError(ValueError):
    """Raised when a requested run or query is outside the review boundary."""


class ReviewData:
    def __init__(self, workspace: Path) -> None:
        self.workspace = workspace.expanduser().resolve()

    @staticmethod
    def _is_within(path: Path, root: Path) -> bool:
        try:
            path.relative_to(root)
            return True
        except ValueError:
            return False

    def resolve_run(self, run_id: str) -> Path:
        if not run_id or run_id == ".":
            candidate = self.workspace
        else:
            relative = Path(run_id)
            if relative.is_absolute():
                raise ReviewDataError("Absolute run paths are not allowed.")
            candidate = (self.workspace / relative).resolve()

        if not self._is_within(candidate, self.workspace):
            raise ReviewDataError("Run path is outside the configured workspace.")
        return candidate

    def _run_id(self, run_root: Path) -> str:
        relative = run_root.resolve().relative_to(self.workspace)
        return "." if str(relative) == "." else relative.as_posix()

    @staticmethod
    def _read_text(path: Path) -> tuple[str, str | None]:
        if not path.is_file():
            return "", None
        try:
            if path.stat().st_size > MAX_ARTIFACT_BYTES:
                return "", f"Artifact is larger than {MAX_ARTIFACT_BYTES} bytes: {path.name}"
            return path.read_text(encoding="utf-8"), None
        except (OSError, UnicodeError) as exc:
            return "", f"Could not read {path.name}: {exc}"

    @classmethod
    def _read_json(cls, path: Path, default: Any) -> tuple[Any, str | None]:
        text, error = cls._read_text(path)
        if error:
            return default, error
        if not text:
            return default, None
        try:
            return json.loads(text), None
        except json.JSONDecodeError as exc:
            return default, f"Invalid JSON in {path.name}: line {exc.lineno}, column {exc.colno}"

    def _safe_file(self, run_root: Path, candidate: Path) -> Path | None:
        try:
            resolved = candidate.expanduser().resolve()
        except OSError:
            return None
        return resolved if self._is_within(resolved, run_root.resolve()) else None

    def _artifact_text(
        self,
        run_root: Path,
        configured_path: Any,
        fallback: Path,
    ) -> tuple[str, str | None]:
        candidate: Path | None = None
        if isinstance(configured_path, str) and configured_path.strip():
            raw = Path(configured_path)
            candidate = raw if raw.is_absolute() else run_root / raw
            candidate = self._safe_file(run_root, candidate)
        if candidate is None or not candidate.is_file():
            candidate = self._safe_file(run_root, fallback)
        if candidate is None:
            return "", "Artifact path is outside the selected run."
        return self._read_text(candidate)

    def _jobs(self, run_root: Path) -> tuple[list[dict[str, Any]], list[str]]:
        errors: list[str] = []
        status, error = self._read_json(run_root / "status.json", [])
        if error:
            errors.append(error)
        summary, error = self._read_json(run_root / "summary.json", {})
        if error:
            errors.append(error)

        raw_jobs: Any = status
        if not isinstance(raw_jobs, list) or not raw_jobs:
            raw_jobs = summary.get("jobs", []) if isinstance(summary, dict) else []
        jobs = [item for item in raw_jobs if isinstance(item, dict)] if isinstance(raw_jobs, list) else []
        return jobs, errors

    @staticmethod
    def _status_counts(jobs: list[dict[str, Any]]) -> dict[str, int]:
        counts: dict[str, int] = {}
        for job in jobs:
            status = str(job.get("status") or "UNKNOWN").upper()
            counts[status] = counts.get(status, 0) + 1
        return counts

    @staticmethod
    def _updated_at(run_root: Path) -> str | None:
        mtimes = []
        for name in ("status.json", "summary.json"):
            path = run_root / name
            if path.is_file():
                try:
                    mtimes.append(path.stat().st_mtime)
                except OSError:
                    pass
        if not mtimes:
            return None
        return datetime.fromtimestamp(max(mtimes), tz=timezone.utc).isoformat()

    def _run_roots(self) -> list[Path]:
        roots: set[Path] = set()
        if (self.workspace / "status.json").is_file() or (self.workspace / "summary.json").is_file():
            roots.add(self.workspace)

        archive = self.workspace / "archive"
        if archive.is_dir():
            archive_root = archive.resolve()
            if not self._is_within(archive_root, self.workspace):
                return sorted(
                    roots,
                    key=lambda item: self._updated_at(item) or "",
                    reverse=True,
                )
            for marker_name in ("summary.json", "status.json"):
                for marker in archive.rglob(marker_name):
                    root = marker.parent.resolve()
                    if self._is_within(root, archive_root):
                        roots.add(root)
        return sorted(
            roots,
            key=lambda item: self._updated_at(item) or "",
            reverse=True,
        )

    def list_runs(self) -> list[dict[str, Any]]:
        runs = []
        for run_root in self._run_roots():
            summary, _ = self._read_json(run_root / "summary.json", {})
            jobs, errors = self._jobs(run_root)
            run_id = self._run_id(run_root)
            result = str(summary.get("result") or ("RUNNING" if jobs else "UNKNOWN")).upper()
            runs.append(
                {
                    "id": run_id,
                    "label": "현재 실행" if run_id == "." else run_root.name,
                    "result": result,
                    "mode": summary.get("mode") if isinstance(summary, dict) else None,
                    "tuner": summary.get("tuner") if isinstance(summary, dict) else None,
                    "critics": summary.get("critics", []) if isinstance(summary, dict) else [],
                    "job_count": len(jobs),
                    "status_counts": self._status_counts(jobs),
                    "updated_at": self._updated_at(run_root),
                    "has_errors": bool(errors),
                }
            )
        return runs

    def get_run(self, run_id: str) -> dict[str, Any]:
        run_root = self.resolve_run(run_id)
        summary, summary_error = self._read_json(run_root / "summary.json", {})
        jobs, errors = self._jobs(run_root)
        if summary_error:
            errors.append(summary_error)
        if not isinstance(summary, dict):
            summary = {}

        job_rows = []
        for job in jobs:
            benchmark = job.get("benchmark") if isinstance(job.get("benchmark"), dict) else {}
            validation = job.get("validation") if isinstance(job.get("validation"), dict) else {}
            critiques = job.get("critiques") if isinstance(job.get("critiques"), dict) else {}
            job_rows.append(
                {
                    "name": str(job.get("name") or ""),
                    "sql_id": job.get("sql_id"),
                    "status": str(job.get("status") or "UNKNOWN").upper(),
                    "retry_count": job.get("retry_count", 0),
                    "executions": job.get("executions", 0),
                    "plan_hash_value": job.get("plan_hash_value"),
                    "tables": job.get("tables", []),
                    "improved": benchmark.get("improved"),
                    "critic_approved": benchmark.get("critic_approved"),
                    "oracle_validation_passed": benchmark.get(
                        "oracle_validation_passed", validation.get("passed")
                    ),
                    "risk": self._highest_risk(critiques),
                    "message": benchmark.get("message") or job.get("error") or "",
                }
            )

        result = str(summary.get("result") or ("RUNNING" if jobs else "UNKNOWN")).upper()
        return {
            "id": self._run_id(run_root),
            "label": "현재 실행" if run_root == self.workspace else run_root.name,
            "result": result,
            "updated_at": self._updated_at(run_root),
            "status_counts": self._status_counts(jobs),
            "summary": summary,
            "jobs": job_rows,
            "errors": sorted(set(errors)),
        }

    @staticmethod
    def _highest_risk(critiques: dict[str, Any]) -> str | None:
        order = {"low": 1, "medium": 2, "high": 3}
        risks = [
            str(item.get("risk") or item.get("risk_level") or "").lower()
            for item in critiques.values()
            if isinstance(item, dict)
        ]
        valid = [risk for risk in risks if risk in order]
        return max(valid, key=order.get) if valid else None

    @staticmethod
    def _display_critic(report: Any) -> dict[str, Any]:
        if not isinstance(report, dict):
            return {}
        approved = report.get("ok")
        if not isinstance(approved, bool):
            approved = report.get("approved")
        if not isinstance(approved, bool):
            approved = None
        return {
            "ok": approved,
            "risk": report.get("risk") or report.get("risk_level"),
            "sum": report.get("sum") or report.get("summary") or "",
            "block": report.get("block") or report.get("blocking_issues") or [],
            "fix": report.get("fix") or report.get("improvement_suggestions") or [],
            "sem": report.get("sem") or report.get("semantic_risks") or [],
            "bench": report.get("bench") or report.get("benchmark_notes") or "",
        }

    def get_query(self, run_id: str, query_name: str) -> dict[str, Any]:
        run_root = self.resolve_run(run_id)
        if (
            not query_name
            or query_name in {".", ".."}
            or Path(query_name).name != query_name
        ):
            raise ReviewDataError("Query name must be a single safe path component.")
        jobs, errors = self._jobs(run_root)
        matching = [job for job in jobs if str(job.get("name") or "") == query_name]
        if not matching:
            raise ReviewDataError("Query is not present in the selected run.")
        job = matching[0]

        original_sql, error = self._artifact_text(
            run_root,
            job.get("input_path"),
            run_root / "tmp" / f"{query_name}.sql",
        )
        if error:
            errors.append(error)
        tuned_sql, error = self._artifact_text(
            run_root,
            job.get("tuned_path"),
            run_root / "B" / f"{query_name}-B.sql",
        )
        if error:
            errors.append(error)

        artifact_paths = {
            "analysis": run_root / "A" / f"{query_name}.json",
            "tuning": run_root / "B" / f"{query_name}-B.json",
            "validation": run_root / "validation" / f"{query_name}.json",
            "benchmark": run_root / "benchmark" / f"{query_name}.json",
            "feedback": run_root / "feedback" / f"{query_name}.json",
            "rag": run_root / "rag" / f"{query_name}.json",
        }
        artifacts: dict[str, Any] = {}
        for key, path in artifact_paths.items():
            payload, error = self._read_json(path, {})
            artifacts[key] = payload if isinstance(payload, (dict, list)) else {}
            if error:
                errors.append(error)

        critique_root = self._safe_file(run_root, run_root / "critique" / query_name)
        raw_critics: dict[str, Any] = {}
        if critique_root and critique_root.is_dir():
            for path in sorted(critique_root.glob("*.json")):
                safe_path = self._safe_file(run_root, path)
                if safe_path is None:
                    continue
                report, error = self._read_json(safe_path, {})
                raw_critics[path.stem] = report
                if error:
                    errors.append(error)
        if not raw_critics and isinstance(job.get("critiques"), dict):
            raw_critics = job["critiques"]
        critics = {
            name: self._display_critic(report)
            for name, report in raw_critics.items()
        }

        validation = artifacts["validation"] or (
            job.get("validation") if isinstance(job.get("validation"), dict) else {}
        )
        benchmark = artifacts["benchmark"] or (
            job.get("benchmark") if isinstance(job.get("benchmark"), dict) else {}
        )
        tuning = artifacts["tuning"] if isinstance(artifacts["tuning"], dict) else {}
        rag = artifacts["rag"] if isinstance(artifacts["rag"], dict) else {}

        return {
            "run_id": self._run_id(run_root),
            "name": query_name,
            "job": job,
            "original_sql": original_sql,
            "tuned_sql": tuned_sql,
            "writer": tuning.get("llm_result", {}),
            "tuning_meta": {key: value for key, value in tuning.items() if key != "llm_result"},
            "critics": critics,
            "validation": validation,
            "benchmark": benchmark,
            "analysis": artifacts["analysis"],
            "feedback": artifacts["feedback"],
            "db_context": rag.get("db_context", {}),
            "rag": rag,
            "raw": {
                "job": job,
                "analysis": artifacts["analysis"],
                "tuning": tuning,
                "critics": raw_critics,
                "validation": validation,
                "benchmark": benchmark,
                "feedback": artifacts["feedback"],
                "rag": rag,
            },
            "errors": sorted(set(errors)),
        }


class ReviewHandler(BaseHTTPRequestHandler):
    server_version = "LLMSQLReview/1.0"

    @property
    def data(self) -> ReviewData:
        return self.server.review_data  # type: ignore[attr-defined]

    def log_message(self, format_string: str, *args: Any) -> None:
        print(f"[ReviewUI] {self.address_string()} - {format_string % args}")

    def _security_headers(self) -> None:
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; script-src 'self'; style-src 'self'; "
            "img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'",
        )
        self.send_header("Cache-Control", "no-store")

    def _send_json(self, payload: Any, status: HTTPStatus = HTTPStatus.OK) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._security_headers()
        self.end_headers()
        self.wfile.write(body)

    def _send_static(self, name: str) -> None:
        allowed = {"index.html", "app.js", "style.css"}
        if name not in allowed:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        path = STATIC_DIR / name
        try:
            body = path.read_bytes()
        except OSError:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", f"{content_type}; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._security_headers()
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        start_time = time.time()
        self._status_code = 500  # Default to error; set to 200 only on success
        try:
            if parsed.path == "/api/health":
                self._status_code = 200
                self._send_json({"ok": True, "workspace": str(self.data.workspace)})
            elif parsed.path == "/api/runs":
                self._status_code = 200
                self._send_json({"runs": self.data.list_runs()})
            elif parsed.path == "/api/run":
                self._status_code = 200
                self._send_json(self.data.get_run(query.get("run", ["."])[0]))
            elif parsed.path == "/api/query":
                name = query.get("name", [""])[0]
                if not name:
                    raise ReviewDataError("Query name is required.")
                self._status_code = 200
                self._send_json(self.data.get_query(query.get("run", ["."])[0], name))
            elif parsed.path == "/metrics":
                self._status_code = 200
                self.send_response(200)
                self.send_header("Content-Type", CONTENT_TYPE_LATEST)
                self._security_headers()
                self.end_headers()
                self.wfile.write(generate_latest())
            elif parsed.path in {"/", "/index.html"}:
                self._status_code = 200
                self._send_static("index.html")
            elif parsed.path == "/app.js":
                self._status_code = 200
                self._send_static("app.js")
            elif parsed.path == "/style.css":
                self._status_code = 200
                self._send_static("style.css")
            else:
                self._status_code = 404
                self.send_error(HTTPStatus.NOT_FOUND)
        except ReviewDataError as exc:
            self._status_code = 400
            self._send_json({"error": str(exc)}, HTTPStatus.BAD_REQUEST)
        except OSError as exc:
            self._status_code = 500
            self._send_json({"error": f"Workspace read failed: {exc}"}, HTTPStatus.INTERNAL_SERVER_ERROR)
        finally:
            duration = time.time() - start_time
            REVIEW_REQUESTS_TOTAL.labels(
                method="GET",
                path=parsed.path,
                status=self._status_code
            ).inc()
            REVIEW_REQUEST_DURATION_SECONDS.labels(
                method="GET",
                path=parsed.path
            ).observe(duration)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Open the local LLM-SQL review dashboard.")
    parser.add_argument("--workspace", type=Path, default=DEFAULT_WORKSPACE)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    data = ReviewData(args.workspace)
    server = ThreadingHTTPServer((args.host, args.port), ReviewHandler)
    server.review_data = data  # type: ignore[attr-defined]
    print(f"Review UI: http://{args.host}:{args.port}")
    print(f"Workspace: {data.workspace}")
    print("Read-only mode. Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
