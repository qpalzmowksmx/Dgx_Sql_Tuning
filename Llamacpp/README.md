# Local GGUF model servers

Public-safe model-server tooling for NVIDIA DGX Spark. The included stacks are:

- `Qwen/`: Qwen writer model, converted to GGUF and served through llama.cpp.
- `DeepSeekV4FlashDgxSpark/`: DeepSeek V4 Flash critic using the optimized
  `satindergrewal/llama.cpp` fork and UD-IQ3_XXS GGUF.
- `Hy3/`: Hy3 IQ1_M critic with the required llama.cpp support and optional
  reasoning/MTP configuration.
- `DeepSeek_V4_Flash_0731/`: DeepSeek V4 Flash 0731 UD-IQ3_XXS served with
  the llama.cpp-compatible runtime.
- `DeepSeek_V4_Flash_0731_DSpark/`: DS4 SSD-streaming runtime used as the
  final writer by `AutorunEnum_Final`.

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

Valid public model names include `Qwen`, `DeepSeekV4FlashDgxSpark`, `Hy3`,
`DeepSeek_V4_Flash_0731`, and `DeepSeek_V4_Flash_0731_DSpark`. Only one stack
should be active at a time because they share ports and unified memory.

The DS4 source is intentionally not vendored in this repository. On an
internet-connected preparation machine, run
`DeepSeek_V4_Flash_0731_DSpark/prepare_online.sh --source-only`, then copy the
prepared directory and separately obtained GGUF files into the closed network.

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
