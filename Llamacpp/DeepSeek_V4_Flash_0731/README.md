# DeepSeek V4 Flash 0731 UD-IQ3_XXS — llama.cpp / DGX Spark

This directory is dedicated to the Unsloth `UD-IQ3_XXS` GGUF. It does not use
the DS4/DSpark runtime and must not contain a DS4 base model or drafter.

## Model files

Copy every downloaded `UD-IQ3_XXS` shard into:

```text
runtime/local-gguf/
```

The start scripts select the single `*UD-IQ3_XXS*-00001-of-*.gguf` entry. They
stop if another quant is mixed into the directory or a different model is
selected explicitly.

## Configuration

On a fresh copy, `start.sh` creates `config.env` from `config.env.example`.
When replacing the old IQ3_S deployment, replace the existing `config.env` as
well:

```bash
cp -f config.env.example config.env
```

The default requests 64K context with q8_0 K/V cache and allows llama.cpp
`--fit` to reduce context as far as 32K when memory is insufficient.

## Run

API only:

```bash
cd WithoutUI
./start.sh
./health_check.sh
```

General chat UI:

```bash
cd WithUI
./start.sh
./health_check.sh
```

The UI uses its own persistent volume and does not inherit SQL prompts or chat
history from the other model stacks.

- API: `http://127.0.0.1:8080/v1/models`
- UI: `http://127.0.0.1:3000`

If the generic llama.cpp image was previously built under the old IQ3_S tag,
`start.sh` re-tags that same image locally. Model weights are not stored in the
image; they remain read-only files under `runtime/local-gguf`.
