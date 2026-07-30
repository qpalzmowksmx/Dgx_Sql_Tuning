#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
REPO_ROOT = ROOT_DIR.parent


def main() -> None:
    load_env_files()
    args = parse_args()

    sql_path = resolve_path(args.sql)
    prompt_path = resolve_path(args.prompt or env("OUTLINE_PROMPT_PATH", "prompts/OutlinePrompt.txt"))
    out_dir = resolve_path(args.out_dir or env("OUTLINE_OUTPUT_DIR", "runtime/outlines"))
    out_dir.mkdir(parents=True, exist_ok=True)

    sql = sql_path.read_text(encoding="utf-8")
    prompt = prompt_path.read_text(encoding="utf-8").strip()
    analysis_payload = load_json(resolve_path(args.analysis)) if args.analysis else {}

    result = call_outline_model(
        prompt=prompt,
        sql=sql,
        sql_path=sql_path,
        analysis_payload=analysis_payload,
    )

    payload = {
        "name": sql_path.stem,
        "source": str(sql_path),
        "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "prompt": {
            "path": str(prompt_path),
            "sha256": hashlib.sha256(prompt.encode("utf-8")).hexdigest(),
            "chars": len(prompt),
        },
        "model": env("MODEL_NAME", "qwen-sql-tuner"),
        "outline": normalise_outline(result),
    }

    json_path = out_dir / f"{sql_path.stem}.outline.json"
    txt_path = out_dir / f"{sql_path.stem}.outline.txt"
    json_path.write_text(json_dumps(payload, pretty=True), encoding="utf-8")
    txt_path.write_text(format_outline_text(payload), encoding="utf-8")

    print(json_path)
    print(txt_path)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate an optional Oracle SQL tuning outline JSON.")
    parser.add_argument("--sql", required=True, help="SQL file to outline")
    parser.add_argument("--analysis", default="", help="Optional analysis JSON file")
    parser.add_argument("--prompt", default="", help="Optional prompt path")
    parser.add_argument("--out-dir", default="", help="Output directory")
    return parser.parse_args()


def call_outline_model(
    prompt: str,
    sql: str,
    sql_path: Path,
    analysis_payload: dict[str, Any],
) -> dict[str, Any]:
    base_url = env("API_BASE_URL", "http://localhost:8080/v1").rstrip("/")
    api_key = env("API_KEY", "your-local-api-key")
    model = env("MODEL_NAME", "qwen-sql-tuner")
    max_tokens = int(env("OUTLINE_MAX_TOKENS", "1200"))
    timeout = int(env("OUTLINE_TIMEOUT_SEC", "600"))

    user_payload = {
        "query_name": sql_path.stem,
        "sql": sql,
        "analysis": analysis_payload,
    }
    request_payload = {
        "model": model,
        "temperature": 0.0,
        "max_tokens": max_tokens,
        "messages": [
            {"role": "system", "content": prompt},
            {"role": "user", "content": json_dumps(user_payload)},
        ],
    }

    request = urllib.request.Request(
        f"{base_url}/chat/completions",
        data=json.dumps(request_payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise RuntimeError(f"outline model call failed: {exc}") from exc

    content = body["choices"][0]["message"]["content"].strip()
    try:
        parsed = extract_json_object(content)
    except (json.JSONDecodeError, ValueError):
        return {
            "ok": False,
            "outline": [],
            "risk": ["model_returned_non_json"],
            "check": ["manual_review_required"],
            "handoff": [],
            "raw_text": content,
        }
    parsed["raw_text"] = content
    return parsed


def normalise_outline(result: dict[str, Any]) -> dict[str, Any]:
    return {
        "ok": as_bool(result.get("ok", False)),
        "outline": as_list(result.get("outline")),
        "risk": as_list(result.get("risk")),
        "check": as_list(result.get("check")),
        "handoff": as_list(result.get("handoff")),
        "raw_text": str(result.get("raw_text") or ""),
    }


def format_outline_text(payload: dict[str, Any]) -> str:
    outline = payload["outline"]
    lines = [
        f"# Outline: {payload['name']}",
        "",
        f"- source: {payload['source']}",
        f"- model: {payload['model']}",
        f"- prompt_sha256: {payload['prompt']['sha256']}",
        f"- ok: {outline['ok']}",
        "",
        "## Outline",
        *(f"- {item}" for item in outline["outline"]),
        "",
        "## Risk",
        *(f"- {item}" for item in outline["risk"]),
        "",
        "## Check",
        *(f"- {item}" for item in outline["check"]),
        "",
        "## Handoff",
        *(f"- {item}" for item in outline["handoff"]),
        "",
    ]
    return "\n".join(lines)


def load_env_files() -> None:
    for env_path in [ROOT_DIR / "config.env", REPO_ROOT / ".env", REPO_ROOT / "AutorunEnum" / ".env"]:
        if not env_path.exists():
            continue
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, raw_value = line.split("=", 1)
            os.environ.setdefault(key.strip(), raw_value.strip().strip('"').strip("'"))


def env(name: str, default: str = "") -> str:
    return os.getenv(name, default)


def resolve_path(value: str | Path) -> Path:
    path = Path(value).expanduser()
    if path.is_absolute():
        return path
    candidates = [
        Path.cwd() / path,
        ROOT_DIR / path,
        REPO_ROOT / path,
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()
    return (ROOT_DIR / path).resolve()


def load_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return payload if isinstance(payload, dict) else {}


def extract_json_object(text: str) -> dict[str, Any]:
    fenced = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
    candidate = fenced.group(1) if fenced else text
    start = candidate.find("{")
    end = candidate.rfind("}")
    if start >= 0 and end >= start:
        candidate = candidate[start : end + 1]
    parsed = json.loads(candidate)
    if not isinstance(parsed, dict):
        raise ValueError("outline response JSON must be an object")
    return parsed


def as_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item) for item in value]
    return [str(value)]


def as_bool(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.strip().lower() in {"1", "true", "yes", "y", "ok", "pass"}
    return bool(value)


def json_dumps(payload: Any, pretty: bool = False) -> str:
    if pretty:
        return json.dumps(payload, ensure_ascii=False, indent=2)
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()
