# syntax=docker/dockerfile:1

ARG CUDA_IMAGE=nvcr.io/nvidia/cuda:13.0.1-devel-ubuntu24.04
FROM ${CUDA_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive
ARG LLAMA_CPP_REPO=https://github.com/ggml-org/llama.cpp.git
ARG LLAMA_CPP_REF=b15ca938ad00aa6b3ee6c2edda7363fd02826b18
ARG CUDA_ARCHITECTURES=121-real
ARG BUILD_JOBS=8

ENV LLAMA_CPP_DIR=/opt/llama.cpp
ENV PATH=/opt/venv/bin:/opt/llama.cpp/build/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/cuda/lib64

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    git \
    git-lfs \
    libcurl4-openssl-dev \
    ninja-build \
    python3 \
    python3-pip \
    python3-venv \
  && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv \
  && /opt/venv/bin/pip install --upgrade pip wheel setuptools \
  && /opt/venv/bin/pip install --upgrade \
    "huggingface_hub[cli]" \
    numpy \
    protobuf \
    safetensors \
    sentencepiece \
    transformers

RUN git clone --filter=blob:none --no-checkout "${LLAMA_CPP_REPO}" "${LLAMA_CPP_DIR}" \
  && git -C "${LLAMA_CPP_DIR}" checkout --detach "${LLAMA_CPP_REF}" \
  && test "$(git -C "${LLAMA_CPP_DIR}" rev-parse HEAD)" = "${LLAMA_CPP_REF}" \
  && if [ -f "${LLAMA_CPP_DIR}/requirements.txt" ]; then /opt/venv/bin/pip install -r "${LLAMA_CPP_DIR}/requirements.txt"; fi \
  && if [ -f "${LLAMA_CPP_DIR}/requirements/requirements-convert_hf_to_gguf.txt" ]; then /opt/venv/bin/pip install -r "${LLAMA_CPP_DIR}/requirements/requirements-convert_hf_to_gguf.txt"; fi \
  && cmake \
    -S "${LLAMA_CPP_DIR}" \
    -B "${LLAMA_CPP_DIR}/build" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCHITECTURES}" \
    -DGGML_CUDA=ON \
    -DGGML_CUDA_FA_ALL_QUANTS=ON \
    -DGGML_NATIVE=ON \
    -DLLAMA_CURL=ON \
    -DLLAMA_BUILD_SERVER=ON \
    -DLLAMA_BUILD_UI=OFF \
    -DLLAMA_USE_PREBUILT_UI=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF \
  && export LD_LIBRARY_PATH="/usr/local/cuda/compat:${LD_LIBRARY_PATH}" \
  && cmake --build "${LLAMA_CPP_DIR}/build" \
    --config Release \
    --target llama-server \
    --parallel "${BUILD_JOBS}" \
  && test -x "${LLAMA_CPP_DIR}/build/bin/llama-server" \
  && "${LLAMA_CPP_DIR}/build/bin/llama-server" --version

WORKDIR /workspace/llamacpp
EXPOSE 8080

CMD ["bash"]
