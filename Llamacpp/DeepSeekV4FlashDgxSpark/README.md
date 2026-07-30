# DeepSeek V4 Flash IQ3_XXS — DGX Spark optimized fork

이 디렉터리는 128 GB NVIDIA DGX Spark 한 대에서
`unsloth/DeepSeek-V4-Flash-GGUF:UD-IQ3_XXS`를 실험하기 위한 독립 구성입니다.
다른 DeepSeek 실행 경로와 독립적으로 사용할 수 있도록 구성되어 있습니다.

설치부터 CUDA 검증, A/B benchmark 판독과 장애 대응까지 순서대로 진행할 때는
[`MANUAL.md`](MANUAL.md)를 사용하세요.

## 반영한 포크

- source: `satindergrewal/llama.cpp`, branch `deepseek-v4-flash`
- pinned commit: `7a02824e968f2ce85ad919169962e0020595d141`
- branch base: 2026-07-10 llama.cpp master (`8f114a9b`)
- changes: fused Sinkhorn, fused DeepSeek V4 hyper-connection ops,
  single-token selected compressed-key gather, fused DSV4 CUDA kernels

마지막 commit은 CUDA용 `DSV4_HC_WEIGHTED_SUM`과 `DSV4_HC_EXPAND` kernel을
추가합니다. 이 디렉터리의 build는 해당 commit에 작은 test-only patch를 적용해
두 op 각각에 `n_tokens=1`, hidden width 128/4096 케이스를 추가합니다. 모델 계산
코드는 바꾸지 않습니다.

AMD 9900X/7900 XTX에서 6.3 -> 9.6 tok/s가 나왔다는 사례는 이 변경을 시험할
근거이지 DGX Spark의 보장 성능은 아닙니다. 포크 commit 자체도 CUDA paired
verification을 후속 작업으로 적고 있으므로 DGX Spark에서는 이 디렉터리의 backend
test와 benchmark로 별도 확인해야 합니다.

## DGX Spark 기본값

- architecture: ARM64, GB10, SM121
- build: CUDA 13.0.1, `GGML_CUDA=ON`, `CMAKE_CUDA_ARCHITECTURES=121`
- model: UD-IQ3_XXS, 약 103 GB decimal
- memory: 128 GB coherent unified memory, `--cpu-moe` 사용 안 함
- fit reserve: 8192 MiB
- context: 64K
- KV: q8_0/q8_0, all-quant Flash Attention build
- batch/ubatch: 1024/256
- generation/prompt threads: 16/20
- mmap: off (공식 llama.cpp DGX Spark benchmark와 동일, matrix에서 on도 비교)
- op offload minimum batch: 32 (upstream default, matrix에서 1도 비교)
- sampling: temperature 1.0, top-p 1.0, top-k/min-p 비활성, penalties 비활성
- thinking: `thinking_mode=thinking`, reproducibility seed 42

이 값은 실행 기준값이지 해당 장비의 최적 온도라는 뜻은 아닙니다. 서버별 최적점을
찾는 3단계 코딩 벤치는 `./scripts/09_temperature_benchmark.sh`를 사용하며 설정은
자동 변경하지 않습니다. 생성된 측정 결과는 공개 저장소에 커밋하지 않습니다.

## Docker 실행

DGX Spark에 NVIDIA Container Toolkit이 준비되어 있어야 합니다.

```bash
cd Llamacpp/DeepSeekV4FlashDgxSpark
cp config.env.example config.env
./scripts/docker_run_all.sh
```

첫 실행은 CUDA image/build와 약 103 GB GGUF 다운로드 때문에 오래 걸립니다.
모델은 별도 named volume에 남아 재사용됩니다. 백그라운드로 실행하려면:

```bash
./scripts/docker_compose_up.sh
./scripts/docker_health_check.sh
```

Open WebUI는 같은 compose 구성에서 함께 실행되며 DGX 로컬 브라우저에서
`http://127.0.0.1:3000`으로 접속합니다. 답변 하단에는 llama.cpp가 반환한 실제
prefill/decode tok/s, 토큰 수, 현재/최대 컨텍스트가 표시됩니다. 수정된 WebUI
frontend 이미지는 `docker compose build open-webui`로 재현할 수 있습니다.

Docker build 단계에서 GPU가 보이지 않아도 SM121을 명시적으로 compile합니다.
runtime에는 `--gpus all`이 필요합니다.

## Native 실행

DGX Spark host에 CUDA 13 toolkit의 `nvcc`, CMake, Git이 있어야 합니다.

```bash
cd Llamacpp/DeepSeekV4FlashDgxSpark
cp config.env.example config.env
./run_all.sh
```

단계별 실행:

```bash
./scripts/01_preflight.sh native
./scripts/02_build_llama_cpp.sh
./scripts/06_verify_backend_ops.sh
./scripts/03_start_server.sh
```

## 실험 kernel 검증

서버를 띄우기 전에 CUDA backend의 fused op를 CPU reference와 비교합니다.

```bash
# native
./scripts/06_verify_backend_ops.sh

# Docker
./scripts/docker_verify_backend_ops.sh
```

`SINKHORN_NORM`, `DSV4_HC_WEIGHTED_SUM`, `DSV4_HC_EXPAND`가 모두 통과해야
합니다. 추가로 weighted-sum/expand의 single-token CUDA 케이스 네 개가 CPU
reference와 일치하고, unsupported가 아닌 것도 확인합니다. 실패하면 이 포크를
운영 critic에 사용하지 말고 검증된 별도 fallback으로 전환합니다.

## API와 AutorunEnum

저장소 루트에서 파일 기반 SQL 점검을 실행하면 이 디렉터리의 headless 구성이
자동으로 선택됩니다. 다른 llama.cpp 모델이 떠 있으면 `modelctl.sh stop` 후 이
모델을 시작하고 `/v1/models`에서 아래 alias가 확인될 때까지 기다립니다.

```bash
cd ${PROJECT_ROOT}
./AutorunEnum_Final/run_files.sh
```

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model":"deepseek-v4-flash-iq3-xxs",
    "messages":[{"role":"user","content":"Reply with exactly OK"}],
    "chat_template_kwargs":{"thinking_mode":"thinking"},
    "temperature":1.0,
    "top_p":1.0,
    "top_k":0,
    "min_p":0.0,
    "presence_penalty":0.0,
    "frequency_penalty":0.0,
    "repeat_penalty":1.0,
    "seed":42,
    "max_tokens":64
  }'
```

`AutorunEnum_Final/.env` 연결값:

```env
CRITIC_DEEPSEEK_API_BASE_URL=http://DGX_HOST:8080/v1
CRITIC_DEEPSEEK_API_KEY=your-local-api-key
CRITIC_DEEPSEEK_MODEL_NAME=deepseek-v4-flash-iq3-xxs
CRITIC_DEEPSEEK_REQUEST_STYLE=deepseek_v4
CRITIC_DEEPSEEK_TEMPERATURE=1.0
CRITIC_DEEPSEEK_TOP_P=1.0
CRITIC_DEEPSEEK_TOP_K=0
CRITIC_DEEPSEEK_MIN_P=0.0
CRITIC_DEEPSEEK_THINKING_MODE=thinking
CRITIC_DEEPSEEK_STRUCTURED_OUTPUT=1
```

기본 bind는 `127.0.0.1`입니다. 다른 장비에서 호출할 때만 신뢰된 내부망과
방화벽을 준비하고 `BIND_ADDRESS=0.0.0.0`으로 바꾸세요.

## 속도 비교

서버를 먼저 내린 뒤 같은 build/model로 generation benchmark를 실행합니다.
동시에 실행하면 103 GB model이 중복 load되어 메모리가 부족합니다.

```bash
# Docker server stop
docker compose --env-file config.env down
./scripts/docker_benchmark.sh

# 또는 native
./scripts/05_benchmark.sh
```

기본 결과의 `tg64`(depth 0)와 `tg64 @ d4096/d8192/d16384/d32768` 행이
generation tok/s 곡선입니다. 포크 전후를 공정하게 비교하려면 model quant,
batch/ubatch, KV type, Flash Attention, power mode를 고정하세요.

전체 검증은 다음 matrix가 자동화합니다.

```bash
# Docker 권장
./scripts/docker_benchmark_matrix.sh

# native
./scripts/07_benchmark_matrix.sh
```

matrix는 같은 GGUF cache로 다음 다섯 경우를 순서대로 측정하고 마지막에 최적화
HEAD build를 남깁니다.

| label | source | mmap | op min batch | 목적 |
|---|---|---:|---:|---|
| `base` | `8f114a9b` | 0 | 32 | 전체 포크 전 기준 |
| `pre_cuda` | `6652af2c` | 0 | 32 | CUDA fused kernel 직전 |
| `head` | `7a02824e` | 0 | 32 | 권장 기본값 |
| `head_mmap` | `7a02824e` | 1 | 32 | mmap 영향 분리 |
| `head_offload1` | `7a02824e` | 0 | 1 | 전역 op offload threshold 영향 분리 |

결과, commit, 드라이버, 전력 모드, 실행 설정은
`logs/benchmarks/<UTC timestamp>-{docker,native}/`에 함께 기록됩니다. selected-key
gather는 깊은 context에서 효과가 커야 하므로 한 depth 숫자보다 전체 곡선을
비교하세요. 생성 결과만 모은 `generation-summary.md`도 자동 생성됩니다.

## 모델 파일 고정 확인

`-hf`는 같은 quant 이름의 최신 repository 파일을 받으므로 장기 실험에는 실제
shard checksum도 보관합니다. 모델을 한 번 load한 뒤 다음 명령을 실행합니다.

```bash
# Docker
./scripts/docker_model_manifest.sh

# native
./scripts/08_model_manifest.sh
```

약 103 GB 전체를 SHA-256으로 읽으므로 시간이 걸립니다. Docker wrapper 결과는
`logs/benchmarks/model-sha256-*.txt`에 저장되고 native 스크립트는 stdout으로
출력합니다.

## OOM 조정 순서

1. `USE_MMAP=1`
2. `FIT_TARGET_MIB=12288`
3. `BATCH_SIZE=512`, `UBATCH_SIZE=128`
4. `CTX_SIZE=32768`, `FIT_MIN_CTX=32768`
5. 그래도 부족하면 이 구성을 중지하고 장비 메모리에 맞는 검증된 fallback 사용

`--cpu-moe`는 discrete GPU + system RAM 분할용 판단이므로 이 DGX Spark UMA
profile의 기본값에는 넣지 않았습니다.

## 출처

- fork commits: https://github.com/satindergrewal/llama.cpp/commits/deepseek-v4-flash/
- GGUF: https://huggingface.co/unsloth/DeepSeek-V4-Flash-GGUF/tree/main/UD-IQ3_XXS
- llama.cpp CUDA build: https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md#cuda
- llama.cpp DGX Spark benchmark: https://github.com/ggml-org/llama.cpp/discussions/16578
- DGX Spark container runtime: https://docs.nvidia.com/dgx/dgx-spark/nvidia-container-runtime-for-docker.html
