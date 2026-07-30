# AutorunEnum Final

Oracle SQL tuning pipeline.

## 1. Install dependency

```bash
cd ${PROJECT_ROOT}
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r AutorunEnum_Final/requirements.txt
```

Do not run `run_oracle.sh`, `run_files.sh`, or `main.py` with `sudo`.
The launchers use `PYTHON_BIN` when explicitly set, otherwise the active
virtualenv, then the repository `.venv`, and finally the system Python.
The selected interpreter is printed before the pipeline starts.

To use a different existing environment without activating it:

```bash
PYTHON_BIN=/absolute/path/to/venv/bin/python3 ./AutorunEnum_Final/run_oracle.sh
```

## 2. Configure Oracle

Copy the public-safe example, then replace every placeholder. You may instead
use the repository root `.env`.

```bash
cp AutorunEnum_Final/.env.example AutorunEnum_Final/.env
ORACLE_USER=app_user
ORACLE_PASSWORD=your-oracle-password
ORACLE_DSN=host.example.com:1521/service_name
```

Optional LLM endpoint:

```bash
API_BASE_URL=http://localhost:8080/v1
API_KEY=your-local-api-key
MODEL_NAME=qwen-sql-tuner
```

Prompt files are loaded automatically from the repository `txt` directory:

```bash
TUNER_PROMPT_PATH=../txt/MasteryPrompt.txt
CRITIC_PROMPT_PATH=../txt/CriticPrompt.txt
```

Keep these file names fixed if you want prompt edits to be picked up without code changes.
The pipeline refreshes the prompt file before each tuner or critic model call.
Each tuning and summary JSON stores the prompt path and SHA-256 hash used for that run.

Machine response contracts are separate from the semantic prompts:

```bash
TUNER_RESPONSE_SCHEMA_PATH=../contracts/tuner_response.schema.json
CRITIC_RESPONSE_SCHEMA_PATH=../contracts/critic_response.schema.json
TUNER_STRUCTURED_OUTPUT=1
CRITIC_STRUCTURED_OUTPUT=1
TUNER_TEMPERATURE=0.6
TUNER_TOP_P=0.95
TUNER_TOP_K=20
TUNER_MIN_P=0.0
TUNER_REPETITION_PENALTY=1.0
TUNER_SEED=42
QWEN_CTX_SIZE=131072
TUNER_THINKING=1
TUNER_REASONING_FORMAT=deepseek
TUNER_MAX_TOKENS=81920
TUNER_CACHE_PROMPT=1
TUNER_TIMEOUT_SEC=10800
```

The same JSON Schema is sent through `response_format` to compatible llama.cpp and vLLM
servers and checked again after generation. Invalid tuner output fails closed by returning the
original SQL; invalid critic output rejects the candidate. DwarfStar is prompt-only by default
because its `response_format` compatibility may differ. Enable it explicitly only after testing:

```bash
CRITIC_DEEPSEEK_STRUCTURED_OUTPUT=1
```

The quality-first closed-network profile runs Qwen3.6 with a 128K context,
thinking enabled, unrestricted server-side reasoning, and an 81,920-token
maximum generation ceiling. The effective ceiling is reduced automatically
when the estimated request plus a safety margin would exceed 128K. The request
contains the active SQL only once; a feedback rewrite adds the original SQL
without duplicating the active candidate. Reasoning is returned separately from
the final structured JSON. Prompt-prefix caching remains enabled for throughput,
but every SQL uses a fresh message list and does not inherit another query's conversation.
The tuner request timeout is three hours so long reasoning is not cut off by
the previous 30-minute operational limit.
DeepSeek and Hy3 reasoning controls stay in their model-specific request
arguments and remain separate from the final critic JSON.

Keep live database metadata outside the prompt files:

```bash
cp ../db_context/catalog.example.json ../db_context/catalog.json
DB_CATALOG_PATH=../db_context/catalog.json
DB_CATALOG_SCHEMA_PATH=../contracts/db_catalog.schema.json
DB_QUERY_CONTEXT_SCHEMA_PATH=../contracts/query_context.schema.json
DB_QUERY_CONTEXT_DIR=../db_context/queries
```

AutorunEnum selects objects referenced by each query, follows explicit dependency entries,
and injects the result as `db_context`. Optional query-specific context files are resolved by
`<SQL_ID>.json` first and `<job-name>.json` second. See `../db_context/README.md`.

Oracle validation loop:

```bash
ORACLE_VALIDATE=1
REQUIRE_ORACLE_VALIDATION=1
VALIDATION_ROW_LIMIT=100000
STORE_SAMPLE_ROWS=0
SAME_SNAPSHOT_VALIDATION=1
ORACLE_CALL_TIMEOUT_MS=60000
BENCHMARK_REPETITIONS=6
BENCHMARK_MODE=full
```

Validation preserves optimizer hints, rejects explicit materialization/result-cache features,
rejects tuned plans containing `TEMP TABLE TRANSFORMATION`, `LOAD AS SELECT`, or
`CURSOR DURATION MEMORY`, and compares original/tuned results in one read-only transaction.
Queries with bind variables require matching values in the per-query context `binds` array.
Validation fails closed when either result contains more than `VALIDATION_ROW_LIMIT` rows;
increase the limit only within the database resource budget. An original query with
`ORDER BY`, `FETCH`, `OFFSET`, or `ROWNUM` must also preserve result order. Result rows
are hashed while streaming and are not saved unless `STORE_SAMPLE_ROWS=1`.
`BENCHMARK_MODE=full` consumes the complete result stream; use `first_n` only when
first-page latency is the intended metric. Benchmarks perform one warm-up, alternate
original/tuned execution order, and compare medians across `BENCHMARK_REPETITIONS` runs.

Sequential local critic loop:

```bash
CRITIC_MODELS=deepseek,hy3
REQUIRE_CRITIC_APPROVAL=1
AUTO_MODEL_SWAP=1
AUTO_STOP_MODELS=1
CRITIC_MAX_TOKENS=4096
CRITIC_DEEPSEEK_API_BASE_URL=http://localhost:8080/v1
CRITIC_DEEPSEEK_MODEL_NAME=deepseek-v4-flash-iq3-xxs
CRITIC_DEEPSEEK_REQUEST_STYLE=deepseek_v4
CRITIC_DEEPSEEK_TEMPERATURE=1.0
CRITIC_DEEPSEEK_TOP_P=1.0
CRITIC_DEEPSEEK_TOP_K=0
CRITIC_DEEPSEEK_MIN_P=0.0
CRITIC_DEEPSEEK_THINKING_MODE=thinking
CRITIC_HY3_API_BASE_URL=http://localhost:8080/v1
CRITIC_HY3_MODEL_NAME=hy3-iq1-m-mtp
CRITIC_HY3_REQUEST_STYLE=hy3
CRITIC_HY3_TEMPERATURE=0.9
CRITIC_HY3_TOP_P=1.0
CRITIC_HY3_TOP_K=0
CRITIC_HY3_MIN_P=0.0
CRITIC_HY3_REASONING_EFFORT=high
```

`CRITIC_DEEPSEEK_REQUEST_STYLE`은 실행 중인 서버가 실제로 지원하는 요청 형식과
일치해야 합니다. 다른 서버를 연결할 때는 해당 서버의 model alias와 reasoning
확장 필드를 먼저 검증하세요.

When the full DeepSeek V4 vLLM profile is running on supported hardware, enable
its recommended sampling and Think High mode:

```bash
CRITIC_DEEPSEEK_API_BASE_URL=http://localhost:8000/v1
CRITIC_DEEPSEEK_MODEL_NAME=deepseek-v4-flash
CRITIC_DEEPSEEK_REQUEST_STYLE=vllm
CRITIC_DEEPSEEK_TEMPERATURE=1.0
CRITIC_DEEPSEEK_TOP_P=1.0
CRITIC_DEEPSEEK_THINKING=1
CRITIC_DEEPSEEK_REASONING_EFFORT=high
```

These request extensions are optional and are not sent to other critic models
unless their corresponding environment variables are set.

## 3. Run

Recommended on the company machine. This path uses the Qwen/critic APIs without
Open WebUI, requires structured JSON responses, performs one Qwen rewrite after
critic feedback, and sends that final rewrite through both critics once more:

```bash
./run_oracle.sh
```

To keep the previous Oracle flow with no critic-feedback rewrite, use:

```bash
./Without_run_oracle.sh
```

Both scripts use each model's `WithoutUI/start.sh` and stop all Llamacpp models
when the run finishes. `run_oracle.sh` defaults to one
`--critic-retune-rounds` pass; override it with `CRITIC_RETUNE_ROUNDS=N`.
`Without_run_oracle.sh` always passes zero rounds.

For the same zero-round Oracle flow followed by an interactive Qwen session:

```bash
./Without_run_oracle_withUi.sh
```

After the pipeline completes, this variant switches back to Qwen, leaves Qwen
and Open WebUI running, and prints `http://127.0.0.1:3000`. Pipeline requests
still use the structured JSON contracts. Stop the UI later with
`../Llamacpp/Qwen/WithUI/stop.sh`.

The Final UI handoff never builds or pulls images. It requires both
`llamacpp-qwen-server:cuda` and
`llm-sql-open-webui:v0.9.4-dgx-stats` to already exist locally; otherwise it
fails before changing the running model state.

With LLM tuning forced:

```bash
TUNER=llm ./run_oracle.sh
```

With SELECT-only benchmark execution:

```bash
TUNER=llm EXECUTE_BENCHMARK=1 ./run_oracle.sh
```

`EXECUTE_BENCHMARK=1` also enables Oracle parse/explain/sample validation before the benchmark.

With Qwen tuning plus sequential DeepSeek/Nemotron critic review:

```bash
TUNER=llm CRITICS=deepseek,nemotron MANUAL_MODEL_SWAP=1 EXECUTE_BENCHMARK=1 ./run_oracle.sh
```

This mode is intended for one large model loaded at a time. The run pauses before Qwen tuning,
then before each critic model. Stop the current model server, start the next one on the configured
OpenAI-compatible endpoint, then press Enter.

Collect SQL used in the last 24 hours from `V$SQL`, sorted by execution count:

```bash
python3 main.py --mode oracle --query-limit 50 --collect-hours 24
```

Use an OpenAI-compatible local LLM endpoint:

```bash
python3 main.py --mode oracle --tuner llm --query-limit 50 --collect-hours 24
```

Run SELECT-only benchmark comparison against Oracle:

```bash
python3 main.py --mode oracle --tuner llm --execute-benchmark --benchmark-row-limit 50
```

Dry-run with local SQL files:

```bash
cd ${PROJECT_ROOT}
./AutorunEnum_Final/run_files.sh
```

`run_files.sh` always resolves relative paths from the `LLM-sql` repository root
and writes the active run to top-level `workspace/`. Its default model flow is:

1. Qwen analyzes the SQL and writes the initial tuned SQL.
2. DeepSeek V4 Flash critiques that candidate.
3. Hy3 IQ1_M critiques the same candidate independently.
4. Qwen receives both saved critic JSON reports and writes the final SQL.
5. DeepSeek and Hy3 review the final Qwen rewrite again.
6. All Llamacpp model containers are stopped for idle standby.

The 128K Qwen tuner and two 64K critic models are not loaded together.
`AUTO_MODEL_SWAP=1` uses each model's `WithoutUI/start.sh`, waits for the exact
`/v1/models` ID, and then starts requests. Each SQL prints a start/completion
line and elapsed time; while a request is running it also prints a heartbeat
every 15 seconds. Oracle validation remains disabled in this offline/manual
path. DeepSeek uses
`thinking_mode=thinking`; Hy3 uses `reasoning_effort=high`. Both keep their official
temperature/top-p values, explicitly disable unrequested candidate filters and penalties,
use seed 42, return compact structured JSON, and have a 4,096 token response limit.
Increase `CRITIC_DEEPSEEK_MAX_TOKENS` only when the extra runtime is intentional.
When a candidate is unchanged, the critic receives the full SQL only once plus
an explicit duplicate marker, preventing long queries from exceeding the 64K
model context merely because original and tuned text are identical.
Transient Qwen and critic HTTP 429/5xx failures are attempted twice by default.
A failed Qwen request returns that query's original SQL and processing continues
with the remaining queries. Status JSON is checkpointed after each tuner and
critic result. Before each run,
the previous active result set is moved intact under `workspace/archive/run-*`
so stale critic files cannot be mistaken for the current run.
Only one process can use a workspace at a time.

Set `AUTO_MODEL_SWAP=0` only when all endpoint changes are managed externally.
Use `CRITIC_RETUNE_ROUNDS=0` to disable the feedback retune explicitly.
Set `AUTO_STOP_MODELS=0` only when the last model must intentionally remain loaded.

## Manual SQL directories

The default source is the top-level `Query/` directory. It is scanned
recursively, so new folders work without a code change:

```text
LLM-sql/
├── Query/
│   ├── existing.sql
│   └── test-five/
│       ├── test-01.sql
│       └── test-02.sql
└── workspace/
```

To include independent directories, list repository-relative or absolute paths
separated by `:`:

```bash
SOURCE_DIRS='Query:ManualQuery:/data/team-sql' ./AutorunEnum_Final/run_files.sh
```

Duplicate files caused by overlapping source roots are collected only once.
Non-SQL files are ignored.

The defaults can be overridden explicitly. For example, to inspect files without
any critic model:

```bash
CRITIC_MODELS= ./AutorunEnum_Final/run_files.sh
```

To opt back into an interactive multi-model review:

```bash
CRITIC_MODELS=deepseek,nemotron MANUAL_MODEL_SWAP=1 ./AutorunEnum_Final/run_files.sh
```

The default is `TUNER=llm`. For a no-model smoke test only, use
`TUNER=local CRITIC_MODELS= CRITIC_RETUNE_ROUNDS=0 ./AutorunEnum_Final/run_files.sh`.

## Output

- `workspace/tmp`: collected original SQL files, numbered by usage rank
- `workspace/A`: human-readable analysis `.txt` plus machine-readable analysis `.json`
- `workspace/B`: latest tuned SQL and JSON plus all Qwen rounds under `rounds/round-N`
- `workspace/validation`: Oracle parse/explain/sample comparison reports
- `workspace/benchmark`: original/tuned metric comparison
- `workspace/critique`: latest critic files plus all reviews under each query's `round-N`
- `workspace/feedback`: compact JSON critic feedback fed back into the next Qwen retry
- `workspace/improved`: SQL that passed the complete execution benchmark
- `workspace/approved`: critic- or Oracle-approved SQL whose performance was not executed
- `workspace/generated`: generated SQL with no critic, Oracle, or performance gate
- `workspace/review`: user review notes for failed verification
- `workspace/failed`: SQL that exhausted retries

`summary.json.result` distinguishes `SUCCESS`,
`ORACLE_VALIDATED_UNBENCHMARKED`, `CRITIC_APPROVED_UNBENCHMARKED`, and
`GENERATED_UNVALIDATED`.
An unexecuted benchmark is therefore reported as unbenchmarked rather than as a
false performance failure.

Human review UI (run from the repository root):

```bash
python3 ReviewUI/server.py
```

Open `http://127.0.0.1:8765`. The UI reads the canonical JSON/SQL artifacts without
changing them, refreshes every five seconds, and also discovers preserved runs under
`workspace/archive/**`. See `../ReviewUI/README.md`.

Repository contracts and dynamic context:

- `../contracts/tuner_response.schema.json`: Qwen writer response contract
- `../contracts/critic_response.schema.json`: critic response contract
- `../contracts/db_catalog.schema.json`: DB catalog file contract
- `../contracts/oracle_db_metadata.template.json`: Qwen-ready Oracle metadata template
- `../contracts/oracle_db_metadata_openwebui_prompt.txt`: JSON-only conversion prompt
- `../contracts/query_context.schema.json`: per-query plan/bind/runtime context contract
- `../db_context/catalog.json`: local live metadata, intentionally ignored by Git
- `../db_context/queries/<SQL_ID>.json`: optional per-query plan/bind/runtime context

See `CRITIC_WORKFLOW.txt` for the non-simultaneous Qwen -> DeepSeek -> Nemotron -> Qwen feedback loop.
See `JSON_OUTPUT_POLICY.txt` for the machine-output format rule.
See `ORACLE_VALIDATION_LOOP.txt` for the mandatory Oracle validation loop.
