# Local GGUF model servers

Public-safe model-server tooling for NVIDIA DGX Spark. The included stacks are:

- `Qwen/`: Qwen writer model, converted to GGUF and served through llama.cpp.
- `DeepSeekV4FlashDgxSpark/`: DeepSeek V4 Flash critic using the optimized
  `satindergrewal/llama.cpp` fork and UD-IQ3_XXS GGUF.
- `Hy3/`: Hy3 IQ1_M critic with the required llama.cpp support and optional
  reasoning/MTP configuration.

All stacks default to loopback-only API and Web UI bindings. Do not expose them
on a public interface without authentication, firewall rules, and transport
security.

## Start and stop

From the `Llamacpp` directory:

```bash
./modelctl.sh start Qwen
./modelctl.sh status
./modelctl.sh stop
```

Valid model names are `Qwen`, `DeepSeekV4FlashDgxSpark`, and `Hy3`. Only one
stack should be active at a time because they share ports and unified memory.

For direct model-specific operation:

```bash
cd Llamacpp/Qwen
cp config.env.example config.env
./scripts/docker_run_all.sh
```

Use the equivalent command in `Hy3/` or
`DeepSeekV4FlashDgxSpark/`. Review every generated `config.env` before starting
a service. Machine-local configuration, model weights, runtime directories,
logs, and benchmark outputs are ignored by Git.

## Endpoints

- OpenAI-compatible API: `http://127.0.0.1:8080/v1`
- Open WebUI: `http://127.0.0.1:3000`

See each model directory's README for model-specific build, memory, validation,
and troubleshooting guidance.

## Public references

- [NVIDIA DGX Spark](https://www.nvidia.com/en-us/products/workstations/dgx-spark/)
- [llama.cpp](https://github.com/ggml-org/llama.cpp)
- [DeepSeek V4 Flash GGUF](https://huggingface.co/unsloth/DeepSeek-V4-Flash-GGUF)
- [Hy3 GGUF](https://huggingface.co/AngelSlim/Hy3-GGUF)

