# DeepSeek V4 Flash IQ3_XXS DGX Spark 운영 매뉴얼

이 문서는 NVIDIA DGX Spark 한 대에서
`unsloth/DeepSeek-V4-Flash-GGUF:UD-IQ3_XXS`를 최적화된 llama.cpp 포크로
빌드하고, CUDA kernel을 검증하고, 서버 성능을 비교한 뒤 운영하는 절차입니다.

대상 디렉터리는 `Llamacpp/DeepSeekV4FlashDgxSpark` 하나이며 별도 legacy
구성은 사용하지 않습니다. discrete GPU용 `--cpu-moe`와 `--n-cpu-moe`는 이
DGX Spark UMA 구성에 넣지 않습니다.

## 1. 고정 구성

| 항목 | 기본값 |
|---|---|
| 장비 | DGX Spark, ARM64, NVIDIA GB10 |
| CUDA architecture | SM121 |
| CUDA image | `nvcr.io/nvidia/cuda:13.0.1-devel-ubuntu24.04` |
| llama.cpp branch | `satindergrewal/llama.cpp:deepseek-v4-flash` |
| 최적화 HEAD | `7a02824e968f2ce85ad919169962e0020595d141` |
| CUDA 직전 비교점 | `6652af2cb162936806e5ac47438c006937156b3f` |
| 포크 전 비교점 | `8f114a9b573b69035299f9b924047f53c1e22c7e` |
| 모델 | `unsloth/DeepSeek-V4-Flash-GGUF:UD-IQ3_XXS` |
| context/KV | 32K, `q8_0/q8_0` |
| batch/ubatch | 1024/256 |
| mmap | off |
| op offload minimum batch | 32 |
| unified-memory environment | on |
| 서버 포트/bind | `8080`, `127.0.0.1` |

최적화 HEAD에는 모델 계산을 바꾸지 않는 test-only patch를 빌드 중 적용합니다.
`DSV4_HC_WEIGHTED_SUM`과 `DSV4_HC_EXPAND` 각각에 실제 decode 형태인
`n_tokens=1`, hidden width 128/4096 케이스를 추가합니다.

## 2. 시작 전 확인

다음 조건이 필요합니다.

- DGX Spark의 Linux ARM64 환경
- NVIDIA GPU driver와 NVIDIA Container Toolkit
- Docker Compose v2
- 시스템 메모리 약 115 GiB 이상 감지
- Docker model volume이 위치할 filesystem에 최소 140 GiB 여유 공간
- Hugging Face와 NVIDIA NGC에 접근할 네트워크

첫 실행은 CUDA image, 세부 build layer와 약 103 GB 모델을 받으므로 시간이
오래 걸립니다. `config.env`의 `HF_TOKEN`은 필요한 경우에만 입력하고 Git에
커밋하지 않습니다.

## 3. 최초 설치와 서버 실행

DGX Spark 터미널에서 실행합니다.

```bash
cd Llamacpp/DeepSeekV4FlashDgxSpark
cp config.env.example config.env
./scripts/docker_run_all.sh
```

이 명령은 다음 순서로 동작합니다.

1. Linux, ARM64, GB10, SM121, 메모리, 디스크와 Docker runtime을 확인합니다.
2. 지정된 llama.cpp commit을 SM121/CUDA 13으로 빌드합니다.
3. single-token 네 건을 포함한 fused CUDA backend test를 실행합니다.
4. test가 모두 통과한 경우에만 `llama-server`를 시작합니다.
5. 처음 사용하는 모델은 named volume으로 내려받아 다음 실행에서 재사용합니다.

백그라운드 실행은 다음 명령을 사용합니다.

```bash
./scripts/docker_compose_up.sh
./scripts/docker_health_check.sh
```

이미 image가 준비된 상태에서 서버만 다시 시작할 때:

```bash
./scripts/docker_start_server.sh
```

서버를 종료할 때:

```bash
docker compose --env-file config.env down
```

model cache named volume은 `down`으로 삭제되지 않습니다.

## 4. CUDA kernel 검증

서버 시작과 별도로 다시 검증하려면:

```bash
./scripts/docker_verify_backend_ops.sh
```

다음 조건이 모두 충족되어야 합니다.

- `SINKHORN_NORM`이 CUDA에서 지원되고 CPU reference와 일치
- `DSV4_HC_WEIGHTED_SUM`이 CUDA에서 지원되고 CPU reference와 일치
- `DSV4_HC_EXPAND`가 CUDA에서 지원되고 CPU reference와 일치
- weighted-sum/expand의 `n_tokens=1` 네 케이스가 `4/4 tests passed`
- 출력에 `not supported`가 없음

하나라도 실패하면 서버를 운영용으로 올리지 않습니다. source patch나 CUDA
kernel 오류를 해결하기 전에는 이 실험 구성을 운영에 사용하지 않습니다.

## 5. 서버 상태와 API 확인

상태 확인:

```bash
./scripts/docker_health_check.sh
```

직접 API를 호출할 때:

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model":"deepseek-v4-flash-iq3-xxs",
    "messages":[{"role":"user","content":"Reply with exactly: OK"}],
    "chat_template_kwargs":{"thinking_mode":"thinking"},
    "temperature":1.0,
    "top_p":1.0,
    "top_k":0,
    "min_p":0.0,
    "presence_penalty":0.0,
    "frequency_penalty":0.0,
    "repeat_penalty":1.0,
    "seed":42,
    "max_tokens":64,
    "stream":false
  }'
```

로그 확인:

```bash
docker compose --env-file config.env logs -f deepseek-v4-flash-dgx-spark
```

## 6. 전체 A/B 성능 검증

AMD 9900X/7900 XTX의 6.3 → 9.6 tok/s 사례는 DGX Spark 성능 보장이 아닙니다.
DGX Spark에서는 동일 모델 cache와 동일 실행 설정으로 직접 비교합니다.

먼저 실행 중인 서버를 내립니다. 서버와 benchmark가 모델을 동시에 load하면
메모리가 부족할 수 있습니다.

```bash
docker compose --env-file config.env down
./scripts/docker_benchmark_matrix.sh
```

matrix는 다음 다섯 경우를 실행합니다.

| label | 비교 내용 | 판독 목적 |
|---|---|---|
| `base` | 포크 전, mmap 0, threshold 32 | 전체 포크 적용 전 기준 |
| `pre_cuda` | CUDA fused kernel 직전 | 최신 CUDA kernel 자체의 효과 분리 |
| `head` | 현재 HEAD, mmap 0, threshold 32 | 운영 기본 후보 |
| `head_mmap` | HEAD, mmap 1 | mmap 영향 분리 |
| `head_offload1` | HEAD, threshold 1 | 전역 op offload 정책 영향 분리 |

모든 경우에서 generation depth는 `0,4096,8192,16384,32768`입니다. 결과는:

```text
logs/benchmarks/<UTC timestamp>-docker/
├── runs.tsv
├── generation-summary.md
├── base.md
├── pre_cuda.md
├── head.md
├── head_mmap.md
├── head_offload1.md
└── *.metadata.txt
```

`generation-summary.md`에서 `tg64`와 `tg64 @ d...` 행을 비교합니다.

| 비교 | 의미 |
|---|---|
| `head` 대 `base` | 포크 전체의 DGX Spark 실효 성능 |
| `head` 대 `pre_cuda` | weighted-sum/expand CUDA kernel의 효과 |
| `head_mmap` 대 `head` | mmap을 켰을 때의 영향 |
| `head_offload1` 대 `head` | threshold 1의 영향 |

판정할 때는 평균값뿐 아니라 표준편차도 확인합니다. 차이가 반복 오차보다 작으면
더 복잡한 설정을 선택하지 않습니다. `head_mmap`이 모든 주요 depth에서 안정적으로
빠르고 OOM이 없다면 `USE_MMAP=1`을 고려합니다. `head_offload1`이 안정적으로
빠른 경우에만 `GGML_OP_OFFLOAD_MIN_BATCH=1`을 적용합니다. 그렇지 않으면 기본값
32를 유지합니다.

matrix가 중간에 실패하면 가능한 경우 최적화 HEAD image를 자동 복원합니다.
정상 완료 후에도 최종 image는 HEAD 상태입니다.

## 7. 단일 HEAD benchmark

커밋 비교 없이 현재 HEAD만 다시 측정할 때:

```bash
docker compose --env-file config.env down
./scripts/docker_benchmark.sh
```

이 명령도 benchmark 전에 fused CUDA test를 먼저 실행합니다.

## 8. 모델 shard 고정

`-hf` 방식은 quant 이름으로 repository 파일을 선택합니다. 장기간 같은 모델 파일을
재현하려면 다운로드가 끝난 뒤 shard SHA-256을 기록합니다.

```bash
docker compose --env-file config.env down
./scripts/docker_model_manifest.sh
```

약 103 GB 전체를 읽으므로 시간이 걸립니다. 결과는 다음에 저장됩니다.

```text
logs/benchmarks/model-sha256-<UTC timestamp>.txt
```

포크 전후 benchmark는 반드시 같은 named volume과 같은 manifest의 모델을
사용해야 합니다.

## 9. AutorunEnum 연결

원격 장비에서 호출할 때 `AutorunEnum_Final/.env`에 다음 값을 사용합니다.

```env
CRITIC_DEEPSEEK_API_BASE_URL=http://DGX_HOST:8080/v1
CRITIC_DEEPSEEK_API_KEY=your-local-api-key
CRITIC_DEEPSEEK_MODEL_NAME=deepseek-v4-flash-iq3-xxs
CRITIC_DEEPSEEK_REQUEST_STYLE=deepseek_v4
CRITIC_DEEPSEEK_TEMPERATURE=1.0
CRITIC_DEEPSEEK_TOP_P=1.0
CRITIC_DEEPSEEK_TOP_K=0
CRITIC_DEEPSEEK_MIN_P=0.0
CRITIC_DEEPSEEK_PRESENCE_PENALTY=0.0
CRITIC_DEEPSEEK_FREQUENCY_PENALTY=0.0
CRITIC_DEEPSEEK_REPETITION_PENALTY=1.0
CRITIC_DEEPSEEK_SEED=42
CRITIC_DEEPSEEK_THINKING_MODE=thinking
CRITIC_DEEPSEEK_STRUCTURED_OUTPUT=1
```

다른 장비에서 접근하려면 `config.env`의 `BIND_ADDRESS=0.0.0.0`으로 바꿀 수
있습니다. 이때 신뢰된 내부망, 방화벽, VPN 또는 인증 reverse proxy를 먼저
준비합니다. 인증 없이 공인망에 직접 노출하지 않습니다.

## 10. 메모리 부족 대응

OOM 또는 model load 실패 시 다음 순서로 조정합니다.

1. 다른 GPU/메모리 사용 프로세스를 종료합니다.
2. `USE_MMAP=1`로 변경합니다.
3. `FIT_TARGET_MIB=12288`로 runtime 여유를 늘립니다.
4. `BATCH_SIZE=512`, `UBATCH_SIZE=128`로 낮춥니다.
5. `CTX_SIZE=16384`, `FIT_MIN_CTX=16384`로 낮춥니다.
6. 그래도 실패하면 이 구성을 중지하고 장비 메모리에 맞는 검증된 별도 fallback을
   사용합니다.

DGX Spark는 CPU와 GPU가 128 GB 통합 메모리를 공유하므로 discrete GPU처럼
MoE expert만 system RAM으로 나누는 `--cpu-moe` 방식을 기본값으로 사용하지
않습니다.

## 11. 설정값 변경 원칙

주요 값은 `config.env`에서만 변경합니다.

| 변수 | 기본값 | 변경 기준 |
|---|---:|---|
| `USE_MMAP` | 0 | matrix에서 mmap 1이 명확히 빠르거나 OOM 대응 시 1 |
| `GGML_OP_OFFLOAD_MIN_BATCH` | 32 | `head_offload1`이 안정적으로 빠를 때만 1 |
| `GGML_CUDA_ENABLE_UNIFIED_MEMORY` | 1 | 진단용 A/B 외에는 1 유지 |
| `FIT_TARGET_MIB` | 8192 | OOM 시 12288 이상 |
| `CTX_SIZE` | 32768 | OOM 시 16384 |
| `BIND_ADDRESS` | `127.0.0.1` | 보호된 원격 접근이 필요할 때만 `0.0.0.0` |

`GGML_CUDA_ENABLE_UNIFIED_MEMORY=0`은 wrapper가 해당 환경변수를 실제로
`unset`합니다. llama.cpp는 값이 아니라 환경변수 존재 여부로 unified allocation을
판단하므로 단순히 문자열 `0`을 전달해서는 비활성화되지 않습니다.

## 12. Native 실행

Docker 대신 DGX Spark host의 CUDA 13 toolkit을 직접 사용할 때:

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

Native A/B matrix와 manifest:

```bash
./scripts/07_benchmark_matrix.sh
./scripts/08_model_manifest.sh
```

## 13. 문제 해결표

| 증상 | 확인 및 조치 |
|---|---|
| preflight가 Linux/ARM64에서 실패 | DGX Spark host에서 실행 중인지 확인 |
| GPU 이름이 GB10이 아님 | 잘못된 장비에서 실행하지 말고 `ALLOW_UNSUPPORTED_HARDWARE`를 상시 사용하지 않음 |
| SM121 build 실패 | CUDA 13 image/toolkit과 driver 상태 확인 |
| `not supported` 출력 | 현재 HEAD와 test patch 적용 여부 확인 후 운영 중단 |
| `4/4 tests passed`가 없음 | single-token CUDA 검증 실패로 간주 |
| model download 중단 | 같은 명령을 다시 실행해 named volume cache 재사용 |
| port 8080 충돌 | 다른 서비스를 내리거나 `PORT` 변경 |
| benchmark가 서버 실행 중이라고 거부 | `docker compose --env-file config.env down` 실행 |
| matrix 중간 실패 | 보존된 결과와 metadata 확인 후 재실행; script가 HEAD image 복원 시도 |
| 다른 장비에서 API 접속 불가 | `BIND_ADDRESS`, 방화벽, Docker publish 확인 |

## 14. 검증 완료 기준

운영 전 다음 항목을 모두 만족해야 합니다.

- preflight 통과
- source commit이 `7a02824e...`와 일치
- fused CUDA test 통과
- single-token test `4/4 tests passed`
- `/v1/models`와 chat completion health check 통과
- `generation-summary.md`에서 HEAD 성능 확인
- OOM, 반복 restart, `not supported` 없음
- 외부 접근 시 네트워크 보호 적용

현재 저장소에서 셸 문법, test patch 순방향/역방향 적용, Compose SM121/commit
렌더링과 설정 토글은 정적으로 검증했습니다. 실제 CUDA build, kernel 실행과 tok/s
수치는 DGX Spark에서 확인해야 합니다.

## 15. 참고 자료

- 최적화 포크: https://github.com/satindergrewal/llama.cpp/commits/deepseek-v4-flash/
- UD-IQ3_XXS 모델: https://huggingface.co/unsloth/DeepSeek-V4-Flash-GGUF/tree/main/UD-IQ3_XXS
- llama.cpp DGX Spark benchmark: https://github.com/ggml-org/llama.cpp/discussions/16578
- llama.cpp CUDA build: https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md#cuda
- DGX Spark container runtime: https://docs.nvidia.com/dgx/dgx-spark/nvidia-container-runtime-for-docker.html
