# DGX Spark Docker operation

The three included model directories use the same operating pattern:

- `llama-server` or its OpenAI-compatible server listens on `127.0.0.1:8080`.
- Open WebUI listens on `127.0.0.1:3000` and starts after the model health check passes.
- Open WebUI data uses the shared `llm-sql-open-webui-data` volume.
- Model and Hugging Face caches remain in their model-specific directories or named volumes.
- Stopping or switching models does not delete persistent volumes.

## Start one model

Run from the `Llamacpp` directory:

```bash
./modelctl.sh start DeepSeekV4FlashDgxSpark
```

Other accepted names are `Hy3` and `Qwen`.
The switch command stops the other model Compose projects first because they share ports 8080 and 3000.

## Check and stop

```bash
./modelctl.sh status
curl -fsS http://127.0.0.1:8080/v1/models
./modelctl.sh stop
```

Open `http://127.0.0.1:3000` in the DGX browser for chat. The root API URL at port 8080 may return 404; `/v1/models` is the health endpoint.

## Configuration

On first start, `config.env` is created from `config.env.example` when a model provides one. These runtime files are ignored by Git. An optional model-local `open-webui.env` can hold Open WebUI settings without committing secrets.

DeepSeek V4 Flash DGX Spark defaults to a 65,536-token context. Both its K and V caches are `q8_0` (8-bit); change those only after checking available unified memory.
