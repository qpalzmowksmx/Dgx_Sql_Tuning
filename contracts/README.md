# Machine contracts

These files define machine structure only. Semantic Oracle tuning rules stay in the English
writer and critic prompts under `txt/`.

- `tuner_response.schema.json`: Qwen writer response
- `critic_response.schema.json`: DeepSeek/Nemotron critic response
- `db_catalog.schema.json`: global Oracle metadata catalog
- `oracle_db_metadata.template.json`: fill-in template for Oracle tables, columns,
  constraints, indexes, partitions, and statistics
- `oracle_db_metadata_openwebui_prompt.txt`: JSON-only Qwen transformation instructions
- `query_context.schema.json`: SQL_ID-specific plan, bind, runtime, and validation context

AutorunEnum reloads writer/critic response schemas before model calls, sends them through
`response_format` when the selected server supports structured output, and validates parsed
responses again. DB context files are validated before any selected metadata is sent to a model.

`contracts/` defines and demonstrates the format; it is not the live-data directory.
Use Qwen to fill `oracle_db_metadata.template.json`, then save the resulting JSON as
`../db_context/catalog.json`. That live file is intentionally ignored by Git so database
metadata and internal names are not committed accidentally. Open WebUI chat cannot write the
repository file by itself; download or copy its JSON response to that path.
