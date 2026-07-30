# Security Policy

## Scope

DGX SQL Tuning processes material that may contain SQL text, database metadata,
bind values, execution plans, credentials, host information, and model download
tokens. None of that operational data belongs in the public repository.

The public repository is limited to source code, JSON Schema contracts,
sanitized examples, prompts, tests, and documentation.

## Safe defaults

- Review UI binds to `127.0.0.1` by default.
- Oracle credentials and API tokens are loaded from ignored local environment files.
- SQL inputs, database context, workspaces, logs, benchmark output, model weights,
  and runtime caches are ignored by Git.
- Pipeline runtime files use restrictive permissions by default.
- Root execution is rejected unless explicitly enabled for recovery.
- Review UI rejects absolute paths, traversal, and artifact access outside its workspace.
- Model output and Oracle validation fail closed when required evidence is missing.

Do not expose model APIs or Review UI on `0.0.0.0` without authentication,
firewall rules, transport security, and an explicit network review.

## Reporting a vulnerability

Do not open a public issue containing credentials, SQL, database identifiers,
internal host details, or exploit instructions.

Use GitHub's private vulnerability reporting or a private security advisory for
this repository. Include:

1. the affected component and version or commit;
2. reproducible steps using synthetic data;
3. the expected and observed security boundary;
4. the potential impact;
5. a proposed mitigation, when available.

Remove all real credentials, customer identifiers, SQL contents, hostnames,
addresses, and database metadata before submitting a report.

## Before publishing changes

Run the unit tests and inspect the staged files:

```bash
python3 -m unittest discover -s AutorunEnum_Final/tests -v
python3 -m unittest discover -s ReviewUI/tests -v
git diff --cached --check
git diff --cached
```

Confirm that no `.env`, `config.env`, SQL input, database context, workspace,
log, benchmark, model, private key, token, or internal URL is staged.

