#!/usr/bin/env python3
"""Fail-fast Oracle capability check used before starting large model containers."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent


def env_files() -> list[Path]:
    candidates: list[Path] = []
    explicit = os.getenv("AUTORUN_ENV_FILE", "").strip()
    if explicit:
        candidates.append(Path(explicit).expanduser())
    candidates.extend((SCRIPT_DIR / ".env", REPO_ROOT / ".env"))
    result: list[Path] = []
    seen: set[Path] = set()
    for candidate in candidates:
        resolved = candidate.resolve()
        if resolved not in seen:
            seen.add(resolved)
            result.append(resolved)
    return result


def setting(name: str, default: str = "") -> str:
    value = os.getenv(name)
    if value is not None:
        return value
    for path in env_files():
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except FileNotFoundError:
            continue
        except OSError as exc:
            raise RuntimeError(f"cannot read environment file {path}: {exc}") from exc
        for raw_line in lines:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, raw_value = line.split("=", 1)
            if key.strip() == name:
                return raw_value.strip().strip('"').strip("'")
    return default


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("files", "oracle"), default="files")
    parser.add_argument("--validation", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        import oracledb
    except ImportError:
        print(
            "[AutorunEnum] Oracle preflight failed: python-oracledb is not installed.",
            file=sys.stderr,
        )
        return 1

    values = {
        "ORACLE_USER": setting("ORACLE_USER"),
        "ORACLE_PASSWORD": setting("ORACLE_PASSWORD"),
        "ORACLE_DSN": setting("ORACLE_DSN"),
    }
    missing = [name for name, value in values.items() if not value]
    if missing:
        print(
            "[AutorunEnum] Oracle preflight failed: missing " + ", ".join(missing),
            file=sys.stderr,
        )
        return 1

    timeout_ms = max(1, int(setting("ORACLE_CALL_TIMEOUT_MS", "60000")))
    try:
        with oracledb.connect(
            user=values["ORACLE_USER"],
            password=values["ORACLE_PASSWORD"],
            dsn=values["ORACLE_DSN"],
        ) as connection:
            connection.call_timeout = timeout_ms
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1 FROM dual")
                if cursor.fetchone() != (1,):
                    raise RuntimeError("SELECT 1 FROM dual returned an unexpected value")
                if args.mode == "oracle":
                    cursor.execute("SELECT 1 FROM v$sql WHERE ROWNUM = 1")
                    cursor.fetchone()
                if args.validation:
                    cursor.execute("EXPLAIN PLAN FOR SELECT 1 FROM dual")
                    cursor.execute("SELECT plan_table_output FROM TABLE(DBMS_XPLAN.DISPLAY())")
                    cursor.fetchall()
                    connection.rollback()
    except Exception as exc:  # Oracle exceptions vary across driver releases.
        print(
            f"[AutorunEnum] Oracle preflight failed: {type(exc).__name__}: {exc}",
            file=sys.stderr,
        )
        return 1

    capabilities = ["connect", "select"]
    if args.mode == "oracle":
        capabilities.append("v$sql")
    if args.validation:
        capabilities.extend(("explain-plan", "dbms-xplan"))
    print("[AutorunEnum] Oracle preflight passed: " + ", ".join(capabilities))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
