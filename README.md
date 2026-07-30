# DGX SQL Tuning

Public-safe tooling and documentation for running local LLM services and an
Oracle SQL tuning workflow on NVIDIA DGX systems.

## Included

- `Llamacpp/`: llama.cpp build, container, server, and smoke-test tooling
- `AutorunEnum_Final/`: SQL tuning pipeline code and tests
- `OutlinePass/`: outline extraction tooling
- `ReviewUI/`: local review UI
- `contracts/`: JSON response contracts
- `db_context/`: database-context helpers (no real query contents)
- `txt/`: public-safe writer/critic prompts and pipeline structure

## Configuration

Copy an appropriate `config.env.example` file to an untracked local
`config.env` or `.env` file, then replace values such as:

- `your-local-api-key`
- `your-deepseek-api-key`
- `your-hy3-api-key`
- `your-oracle-password`
- `${PROJECT_ROOT}`

Never commit real credentials, connection strings, host addresses, model
download tokens, SQL inputs, generated results, or internal repository URLs.

## Public-safety scope

Operational logs, benchmark outputs, source SQL, database query backups,
machine-specific setup, monitoring data, local workspaces, and private
environment files are intentionally excluded from this repository.
