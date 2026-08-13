# DeepSeek V4 Flash 0731 DSpark — general LLM chat

This directory is a standalone Open WebUI chat stack for one NVIDIA DGX Spark.
It contains no SQL writer/critic wrapper, database prompt, or AutorunEnum entry
point.

The directory contains the checkpoint-matched pair below:

```text
models/DeepSeek-V4-Flash-Layers37-42Q4KExperts-OtherExpertLayersIQ2XXSGateUp-Q2KDown-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-fixed-0731.gguf
models/DeepSeek-V4-Flash-DSpark-support-0731.gguf
```

Do not place the Unsloth `UD-IQ3_XXS` shards here. Those belong in the sibling
`DeepSeek_V4_Flash_0731/runtime/local-gguf` llama.cpp deployment.

## Prepare and build

On an internet-connected preparation machine:

```bash
./prepare_online.sh --all
```

After copying this whole directory and the required CUDA base image to DGX:

```bash
cp config.env.example config.env
./build.sh
```

The first start can build automatically when `DS4_AUTO_BUILD=1`, but an offline
DGX still needs the CUDA base image and bundled `vendor/ds4-src` tree.

The source is pinned to `antirez/ds4` commit
`b7e9f0091139999b6c070a57590c447c5741da5c`. When enabled, the support GGUF is
passed with `--mtp` and `--dspark` selects the DSpark verifier. Do not add the
old MTP or the separate bleysg drafter.

`runtime.env` owns the source commit, model filenames, and image tag. It is
loaded after the local `config.env`, so an existing config from the
old drafter stack cannot silently switch the runtime back. User-specific ports,
tokens, volume names, and timeouts remain in `config.env`.

## Chat

```bash
cd WithUI
./start.sh
./health_check.sh
```

- Open WebUI: `http://127.0.0.1:3000`
- Model API: `http://127.0.0.1:8080/v1/models`

Stop with `WithUI/stop.sh`. The model KV cache and chat data volumes are
preserved. The UI uses a dedicated data volume, so other Open WebUI model
presets and SQL-oriented system prompts are not inherited.

Actual single-Spark testing showed that this approximately 97.6 GB mixed base
GGUF plus the support GGUF cannot remain resident with useful KV capacity on a
128 GB system. The validated default is therefore 32K context, DS4 SSD streaming
with a 48 GB expert cache, and `DS4_ENABLE_DSPARK=0`. Client requests still
control temperature and top-p. Re-enable DSpark only with a proven smaller
matched pair or a larger/multi-node memory target.

At 32K context the DS4 runtime uses normal high-effort thinking. Its distinct
Think Max mode requires a 393216-token context, so requesting `max` from a chat
client at 32K is recorded as an effective high-effort run.
