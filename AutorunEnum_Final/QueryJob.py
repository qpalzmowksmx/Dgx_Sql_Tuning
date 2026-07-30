from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from EnumAuto import QueryStatus


@dataclass
class QueryJob:
    name: str
    source_path: Path
    input_path: Path
    sql_id: str = ""
    child_number: int = 0
    plan_hash_value: int = 0
    parsing_schema_name: str = ""
    executions: int = 0
    metrics: dict[str, Any] = field(default_factory=dict)
    status: QueryStatus = QueryStatus.WAITING
    retry_count: int = 0
    tables: list[str] = field(default_factory=list)
    findings: list[str] = field(default_factory=list)
    analysis_path: Path | None = None
    tuned_path: Path | None = None
    benchmark_path: Path | None = None
    benchmark: dict[str, Any] = field(default_factory=dict)
    validation_path: Path | None = None
    validation: dict[str, Any] = field(default_factory=dict)
    critique_paths: dict[str, str] = field(default_factory=dict)
    critiques: dict[str, Any] = field(default_factory=dict)
    feedback_path: Path | None = None
    error: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "source_path": str(self.source_path),
            "input_path": str(self.input_path),
            "sql_id": self.sql_id,
            "child_number": self.child_number,
            "plan_hash_value": self.plan_hash_value,
            "parsing_schema_name": self.parsing_schema_name,
            "executions": self.executions,
            "metrics": self.metrics,
            "status": self.status.name,
            "retry_count": self.retry_count,
            "tables": self.tables,
            "findings": self.findings,
            "analysis_path": str(self.analysis_path) if self.analysis_path else None,
            "tuned_path": str(self.tuned_path) if self.tuned_path else None,
            "benchmark_path": str(self.benchmark_path) if self.benchmark_path else None,
            "benchmark": self.benchmark,
            "validation_path": str(self.validation_path) if self.validation_path else None,
            "validation": self.validation,
            "critique_paths": self.critique_paths,
            "critiques": self.critiques,
            "feedback_path": str(self.feedback_path) if self.feedback_path else None,
            "error": self.error,
        }
