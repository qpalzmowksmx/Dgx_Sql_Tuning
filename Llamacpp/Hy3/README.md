# Hy3 IQ1_M MTP — llama.cpp on DGX Spark

이 디렉터리는 사용자가 지정한
[`AngelSlim/Hy3-GGUF`의 `Hy3-IQ1_M-mtp.gguf`](https://huggingface.co/AngelSlim/Hy3-GGUF?show_file_info=Hy3-IQ1_M-mtp.gguf)를
128 GB NVIDIA DGX Spark 한 대에서 실행하는 구성입니다.

## 결론

이 파일은 llama.cpp용 GGUF가 맞습니다. 다만 Hy3는 새 `hy_v3`
아키텍처라 과거 llama.cpp 빌드에서는 열리지 않습니다. Hy3와 내장 MTP
self-speculative decoding 지원은 2026-07-13에 upstream llama.cpp
[PR #25395](https://github.com/ggml-org/llama.cpp/pull/25395)로 병합됐습니다.

다만 GGUF 저장소의 공식 build에는 upstream 병합분에 아직 없는 Hy3 전용
thinking/tool-call 응답 parser도 들어 있습니다. 이 구성은 모델 배포자가 검증한
base commit `19bba67c1f4db723c60a0d421aa0788bf4ddc699`에 공식 patch 2개를
적용합니다. patch URL은 모델 revision으로, 각 파일은 SHA-256으로 고정했습니다.

대상 파일을 다음 값으로 고정했습니다.

- 모델: Hy3, 295B total / 21B active MoE, MTP layer 1개
- 파일: `Hy3-IQ1_M-mtp.gguf`
- 크기: 91,756,066,624 bytes = 약 91.76 GB / 85.46 GiB
- SHA-256: `f3b9ab6394d9de03394b9d95aa75af42ca7025711cf8418857eddd0d213e5f13`
- 모델 저장소 revision: `218c93f0fb5227553b67e556b01dfe70fb70cf30`
- 전체 지원 context: 262,144 tokens; 이 장비의 안전한 시작값은 32,768

현재 개발 Mac에는 약 70 GiB만 남아 있어 이 85.46 GiB 파일을 실제로 내려받지
않았습니다. 아래 스크립트는 DGX Spark에서 처음 실행할 때 모델을 named volume 또는
`runtime/models/`에 이어받기 가능한 방식으로 다운로드하고 SHA-256까지 검증합니다.

## Docker 실행 — 권장

DGX Spark에 Docker, NVIDIA Container Toolkit과 충분한 디스크 공간이 있어야 합니다.
NVIDIA 공식 DGX Spark 문서와 같은 CUDA image를 사용합니다. NGC 인증 오류가 나는
환경에서는 먼저 로그인하고, GPU container 접근을 한 번 확인하세요.

```bash
docker login nvcr.io
# Username: $oauthtoken, Password: NGC API key

docker run --rm --gpus=all \
  nvcr.io/nvidia/cuda:13.0.1-devel-ubuntu24.04 nvidia-smi
```

공개 CUDA image가 로그인 없이 받아지는 환경이면 `docker login`은 생략할 수 있습니다.

```bash
cd Llamacpp/Hy3
cp config.env.example config.env
./scripts/docker_run_all.sh
```

첫 실행은 CUDA 13/SM121-real llama.cpp image를 빌드하고 약 91.76 GB를 다운로드하므로
오래 걸립니다. 전송이 끊기면 같은 명령을 다시 실행하면 `.partial` 파일부터
이어받습니다. 백그라운드 실행은 다음과 같습니다.

```bash
./scripts/docker_compose_up.sh
./scripts/docker_logs.sh
```

모델과 image가 이미 준비된 뒤 서버만 다시 올릴 때:

```bash
./scripts/docker_start_server.sh
```

## Native 실행

호스트에 CUDA 13 toolkit의 `nvcc`, CMake, Git, curl이 있어야 합니다.

```bash
cd Llamacpp/Hy3
cp config.env.example config.env
./run_all.sh
```

단계별 실행도 가능합니다.

```bash
./scripts/01_preflight.sh native
./scripts/02_build_llama_cpp.sh
./scripts/03_download_model.sh
./scripts/04_start_server.sh
```

## 준비 확인과 API 호출

다른 터미널에서:

```bash
# Docker
./scripts/docker_health_check.sh

# Native
./scripts/05_health_check.sh
```

이 검사는 `/v1/models`뿐 아니라 실제 생성 결과가 정확히 `OK`인지 확인합니다.
최초 설치 후 또는 patch/config를 바꾼 뒤에는 reasoning과 tool-call parser까지 검사하세요.

```bash
# Docker
./scripts/docker_smoke_test.sh

# Native
./scripts/07_smoke_test.sh
```

스모크 테스트는 일반 생성, `reasoning_content` 분리, 강제 Oracle 도구호출을 각각
검증합니다. 모델이 내려받아지고 서버가 준비된 뒤 실행해야 합니다.

직접 호출할 때 `reasoning_effort`는 `no_think`, `low`, `high` 중 하나를 씁니다.

서버 전체 기본값을 `high`로 고정하고 요청에서 값을 생략해도 사고 모드를 쓰려면
레거시 파일을 보존한 별도 Reasoning 프로필을 실행합니다.

```bash
./Reasoning-start.sh
./Reasoning-smoke-test.sh
```

이 프로필은 `Reasoning-docker-compose.yml`, `docker/Reasoning-Dockerfile`,
`Reasoning-config.env`를 사용하며 기존 `docker-compose.yml`과 Dockerfile은
변경하지 않습니다. 서버에는 공식 llama.cpp 옵션과 같은
`LLAMA_ARG_CHAT_TEMPLATE_KWARGS={"reasoning_effort":"high"}`가 설정됩니다.

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model":"hy3-iq1-m-mtp",
    "messages":[{"role":"user","content":"이 Oracle SQL의 병목을 찾아줘."}],
    "chat_template_kwargs":{"reasoning_effort":"high"},
    "temperature":0.9,
    "top_p":1.0,
    "top_k":0,
    "min_p":0.0,
    "presence_penalty":0.0,
    "frequency_penalty":0.0,
    "repeat_penalty":1.0,
    "seed":42,
    "max_tokens":4096,
    "stream":false
  }'
```

서버 기본값도 같은 프로필입니다. `top_k=0`, `min_p=0.0`, 두 OpenAI
penalty의 0, `repeat_penalty=1.0`을 명시해 llama.cpp의 추가 후보 제한과
반복 페널티를 비활성화합니다. SQL 튜닝 반복 비교를 위해 seed는 42입니다.

이 값은 실행 기준값이며 현재 장비의 최적 온도를 보장하지 않습니다. 서버별 최적점을
찾는 3단계 코딩 벤치는 `./scripts/08_temperature_benchmark.sh`를 사용합니다. 설정은
자동 변경하지 않으며 생성된 측정 결과는 공개 저장소에 커밋하지 않습니다.

기본 bind는 `127.0.0.1`입니다. 다른 장비에서 접근할 때만 신뢰된 내부망,
방화벽 또는 인증 reverse proxy를 준비한 뒤 `config.env`에서 Docker는
`BIND_ADDRESS=0.0.0.0`, native는 `HOST=0.0.0.0`으로 바꾸세요.
llama-server 자체 API key도 함께 설정하지 않으면 공인망에 노출하면 안 됩니다.

이 재현성 build는 외부 UI asset을 추가로 받지 않도록 내장 Web UI를 끄고
OpenAI-compatible API server만 만듭니다.

## MTP와 메모리 기본값

요청한 파일은 MTP 헤드를 포함하므로 기본값은 다음과 같습니다.

```env
ENABLE_MTP=1
SPEC_DRAFT_N_MAX=3
SPEC_DRAFT_N_MIN=1
SPEC_DRAFT_P_MIN=0.75
```

PR 작성자의 검증에서는 이 모델의 `p-min=0`이 오히려 non-MTP보다 느렸고,
`0.75`에서 높은 acceptance와 약 26–37% 향상이 관측됐습니다. 이는 RTX 5090의
한 테스트 결과이며 DGX Spark 성능 보장은 아닙니다. MTP 효과는 실제 SQL prompt로
별도 비교해야 합니다.

128 GB unified memory의 시작 설정은 32K context와 main/draft KV 모두
`q8_0`입니다. OOM이면 다음 순서로 낮춥니다.

1. `CTX_SIZE=24576`, 필요하면 `16384`
2. `BATCH_SIZE=512`, `UBATCH_SIZE=128`
3. `FIT_TARGET_MIB=12288`
4. MTP 없이 진단하려면 `ENABLE_MTP=0`

품질을 유지하려면 weight quant를 더 낮추기 전에 context와 batch부터 줄이는 편이
낫습니다. `FIT=1`은 여유가 부족할 때 context를 `FIT_MIN_CTX=16384`까지 자동으로
줄일 수 있습니다.

사전검사는 설치 메모리 총량과 별도로 현재 `MemAvailable + SwapFree`가 100 GiB
이상인지 확인합니다. DGX Spark의 UMA에서 다른 대형 작업이 실행 중이면 먼저
종료하세요. NVIDIA 안내대로 단순 GPU 전용 메모리 수치만 사용하지 않습니다.

디스크 검사는 최초에는 125 GiB를 요구하지만, 모델 또는 `.partial` 다운로드가
이미 있으면 남은 다운로드 크기와 25 GiB의 사후 여유 공간만 요구합니다. 따라서
정상 다운로드가 끝난 뒤 여유 공간이 125 GiB 아래로 내려가도 재시작이 차단되지
않습니다.

## 다운로드 무결성

다운로더는 고정 revision URL을 사용하고 완료 후 85.46 GiB 전체를 SHA-256으로
읽습니다. 검증 marker가 있으면 다음 시작에서는 크기만 확인합니다. 원할 때 전체를
다시 검증할 수 있습니다.

```bash
# Docker
./scripts/docker_model_manifest.sh

# Native
./scripts/06_model_manifest.sh
```

크기 또는 SHA-256 불일치는 네트워크 재시도로 해결되지 않는 데이터 오류로
분류합니다. Docker container는 같은 85.46 GiB 파일을 무한히 재검증하지 않고
유휴·unhealthy 상태로 남습니다. 로그에 표시된 파일을 확인하려면:

```bash
./scripts/docker_logs.sh
./scripts/docker_shell.sh
# /models에서 문제로 표시된 파일을 다른 위치로 옮기거나 삭제한 뒤 exit
docker compose --env-file config.env -f docker-compose.yml restart hy3
```

`curl` 전송 중단처럼 재개 가능한 오류는 기존처럼 container 재시작 후 `.partial`
파일에서 이어받습니다.

모델 저장소가 만들어진 지 얼마 되지 않아 2026-07-14 확인 시 Hugging Face의 일부
대용량 파일 보안 스캔은 아직 queued 상태였습니다. GGUF는 pickle 실행 파일은 아니지만,
이 구성은 공급망 변경을 피하려고 revision, 크기와 SHA-256을 모두 고정합니다.

## 출처

- Hy3 GGUF/model instructions: https://huggingface.co/AngelSlim/Hy3-GGUF
- Hy3 base model card: https://huggingface.co/tencent/Hy3
- llama.cpp Hy3 merge: https://github.com/ggml-org/llama.cpp/pull/25395
- pinned official build script/patches: https://huggingface.co/AngelSlim/Hy3-GGUF/tree/main/patches
- llama-server usage: https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
- NVIDIA DGX Spark container runtime: https://docs.nvidia.com/dgx/dgx-spark/nvidia-container-runtime-for-docker.html
- NVIDIA DGX Spark SM121 build target: https://docs.nvidia.com/dgx/dgx-spark-porting-guide/porting/compilation.html
- NVIDIA DGX Spark UMA memory guidance: https://docs.nvidia.com/dgx/dgx-spark/known-issues.html
