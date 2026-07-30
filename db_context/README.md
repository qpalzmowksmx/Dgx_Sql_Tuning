# DB context

Keep live Oracle metadata outside the system prompts.
No live `catalog.json` or per-query JSON is committed; only examples and contracts are present.

1. Copy `catalog.example.json` to `catalog.json`.
2. Populate it from the target Oracle database.
3. Optionally add a per-query file under `queries/` named `<SQL_ID>.json` or `<job-name>.json`.
4. Set `DB_CATALOG_PATH` and `DB_QUERY_CONTEXT_DIR` only when using non-default paths.

## Build `catalog.json` with Qwen and Open WebUI

`Llamacpp/Qwen/run_all.sh` starts the native llama.cpp API only; it does not start
Open WebUI. On the DGX, start the UI variant instead:

```bash
cd ~/Documents/LLM-sql/Llamacpp/Qwen/WithUI
./start.sh
```

Open `http://127.0.0.1:3000`, provide these two files to Qwen, and then provide the
exported Oracle dictionary metadata:

- `../../../contracts/oracle_db_metadata.template.json`
- `../../../contracts/oracle_db_metadata_openwebui_prompt.txt`

Save Qwen's JSON-only response as:

```text
~/Documents/LLM-sql/db_context/catalog.json
```

Ordinary Open WebUI chat has no permission to write that host path automatically.
Download the response or copy it into `catalog.json`; AutorunEnum validates it against
`contracts/db_catalog.schema.json` before injecting it into a model. Replace every
template placeholder, use `null` for unknown scalar values, and never add credentials
or production row data.

`AutorunEnum` selects catalog objects referenced by each SQL statement and follows explicit
`dependencies` entries. The selected metadata is injected into the model user payload as
`db_context`; the model does not choose or read files itself.

The `binds` section is model/critic evidence. The current Oracle sample and benchmark runner
does not automatically execute production bind values from this file; bind-heavy SQL therefore
requires an explicitly reviewed execution fixture or manual equivalence benchmark.

Recommended catalog content:

- exact owner, object name, object type, and view definition
- columns with data type, length, precision, scale, nullable, and default
- primary, unique, foreign-key, and check constraints
- index column order, direction, uniqueness, and function expressions
- partition keys and partition statistics
- table and column statistics, histograms, and capture time
- synonyms and their resolved targets
- relevant optimizer and NLS parameters

Recommended per-query content:

- bind names, data types, representative value distributions, and capture time
- DBMS_XPLAN output with predicates, aliases, A-Rows, E-Rows, and Starts
- SQL Monitor or V$SQL metrics
- validation feedback tied to the same SQL_ID and child cursor

Do not store passwords, unredacted personal data, or unrestricted production rows here.
Use minimal anonymized samples only when value semantics are necessary.
