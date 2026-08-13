ARG CUDA_IMAGE=nvcr.io/nvidia/cuda:13.0.1-devel-ubuntu24.04
FROM ${CUDA_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive

ARG LLAMA_CPP_REPO=https://github.com/satindergrewal/llama.cpp.git
ARG LLAMA_CPP_BRANCH=deepseek-v4-flash
ARG LLAMA_CPP_REF=7a02824e968f2ce85ad919169962e0020595d141

ARG CUDA_ARCHITECTURES=121a-real
ARG GGML_CUDA_FA_ALL_QUANTS=1
ARG GGML_NATIVE=1
ARG BUILD_JOBS=8

ENV LLAMA_CPP_DIR=/opt/llama.cpp
ENV PATH=/opt/llama.cpp/build/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/compat:/usr/local/cuda/lib64

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        git \
        libssl-dev \
        ninja-build \
    && rm -rf /var/lib/apt/lists/*

# llama.cpp 내려받기 및 커밋 고정
RUN set -eux; \
    git clone \
        --filter=blob:none \
        --single-branch \
        --branch "${LLAMA_CPP_BRANCH}" \
        "${LLAMA_CPP_REPO}" \
        "${LLAMA_CPP_DIR}"; \
    \
    git -C "${LLAMA_CPP_DIR}" checkout \
        --detach "${LLAMA_CPP_REF}"; \
    \
    actual_ref="$(git -C "${LLAMA_CPP_DIR}" rev-parse HEAD)"; \
    echo "Requested commit:   ${LLAMA_CPP_REF}"; \
    echo "Checked-out commit: ${actual_ref}"; \
    test "${actual_ref}" = "${LLAMA_CPP_REF}"

# CMake 구성
RUN set -eux; \
    fa_quants=OFF; \
    native_flag=OFF; \
    \
    if [ "${GGML_CUDA_FA_ALL_QUANTS}" = "1" ]; then \
        fa_quants=ON; \
    fi; \
    \
    if [ "${GGML_NATIVE}" = "1" ]; then \
        native_flag=ON; \
    fi; \
    \
    echo "CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES}"; \
    echo "GGML_CUDA_FA_ALL_QUANTS=${fa_quants}"; \
    echo "GGML_NATIVE=${native_flag}"; \
    \
    cmake \
        -S "${LLAMA_CPP_DIR}" \
        -B "${LLAMA_CPP_DIR}/build" \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCHITECTURES}" \
        -DGGML_CUDA=ON \
        -DGGML_CUDA_FA_ALL_QUANTS="${fa_quants}" \
        -DGGML_NATIVE="${native_flag}" \
        -DLLAMA_OPENSSL=ON \
        -DLLAMA_BUILD_COMMON=ON \
        -DLLAMA_BUILD_TOOLS=ON \
        -DLLAMA_BUILD_SERVER=ON \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=OFF \
        -DLLAMA_BUILD_APP=OFF \
        -DLLAMA_BUILD_UI=OFF \
        -DLLAMA_USE_PREBUILT_UI=OFF

# Runtime image only needs the API server.
RUN set -eux; \
    cmake \
        --build "${LLAMA_CPP_DIR}/build" \
        --config Release \
        --target llama-server \
        --parallel "${BUILD_JOBS}"

# 실행파일 생성 확인
RUN set -eux; \
    test -x "${LLAMA_CPP_DIR}/build/bin/llama-server"; \
    "${LLAMA_CPP_DIR}/build/bin/llama-server" --version

# DGX 런타임에서는 컨테이너에 주입된 호스트 드라이버 라이브러리를 우선 사용
ENV LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/cuda/lib64

COPY scripts/ /opt/dsv4-dgx-wrapper/scripts/

RUN chmod +x /opt/dsv4-dgx-wrapper/scripts/*.sh

WORKDIR /opt/dsv4-dgx-wrapper

EXPOSE 8080

CMD ["/opt/dsv4-dgx-wrapper/scripts/03_start_server.sh"]
