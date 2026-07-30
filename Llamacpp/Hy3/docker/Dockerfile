ARG CUDA_IMAGE=nvcr.io/nvidia/cuda:13.0.1-devel-ubuntu24.04
FROM ${CUDA_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive
ARG LLAMA_CPP_REPO=https://github.com/ggml-org/llama.cpp.git
ARG LLAMA_CPP_BRANCH=master
ARG LLAMA_CPP_REF=19bba67c1f4db723c60a0d421aa0788bf4ddc699
ARG HY3_PATCH_BASE_URL=https://huggingface.co/AngelSlim/Hy3-GGUF/raw/218c93f0fb5227553b67e556b01dfe70fb70cf30/patches
ARG HY3_PATCH_01_FILE=01-hyv3-arch.patch
ARG HY3_PATCH_01_SHA256=23d9def340b452a4bad4900ed20f81d6fdfaf2954b91eae30cf1a0dd0daa21ca
ARG HY3_PATCH_02_FILE=02-hyv3-mtp-tools.patch
ARG HY3_PATCH_02_SHA256=51dea330aa41548d13c21535a7e5e0227f9ae3a182fc5e3cc241adee5ed8b0f7
ARG CUDA_ARCHITECTURES=121-real
ARG GGML_CUDA_FA_ALL_QUANTS=1
ARG GGML_NATIVE=1

ENV LLAMA_CPP_DIR=/opt/llama.cpp
ENV PATH=/opt/llama.cpp/build/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/cuda/lib64

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    git \
    ninja-build \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /tmp/hy3-patches \
  && curl -fsSL --retry 5 --retry-all-errors \
      --output "/tmp/hy3-patches/${HY3_PATCH_01_FILE}" \
      "${HY3_PATCH_BASE_URL}/${HY3_PATCH_01_FILE}" \
  && curl -fsSL --retry 5 --retry-all-errors \
      --output "/tmp/hy3-patches/${HY3_PATCH_02_FILE}" \
      "${HY3_PATCH_BASE_URL}/${HY3_PATCH_02_FILE}" \
  && printf '%s  %s\n' "${HY3_PATCH_01_SHA256}" "/tmp/hy3-patches/${HY3_PATCH_01_FILE}" \
      | sha256sum --check --strict - \
  && printf '%s  %s\n' "${HY3_PATCH_02_SHA256}" "/tmp/hy3-patches/${HY3_PATCH_02_FILE}" \
      | sha256sum --check --strict -

RUN git clone --filter=blob:none --single-branch --branch "${LLAMA_CPP_BRANCH}" \
      "${LLAMA_CPP_REPO}" "${LLAMA_CPP_DIR}" \
  && git -C "${LLAMA_CPP_DIR}" checkout --detach "${LLAMA_CPP_REF}" \
  && test "$(git -C "${LLAMA_CPP_DIR}" rev-parse HEAD)" = "${LLAMA_CPP_REF}" \
  && git -C "${LLAMA_CPP_DIR}" apply --check "/tmp/hy3-patches/${HY3_PATCH_01_FILE}" \
  && git -C "${LLAMA_CPP_DIR}" apply "/tmp/hy3-patches/${HY3_PATCH_01_FILE}" \
  && git -C "${LLAMA_CPP_DIR}" apply --check "/tmp/hy3-patches/${HY3_PATCH_02_FILE}" \
  && git -C "${LLAMA_CPP_DIR}" apply "/tmp/hy3-patches/${HY3_PATCH_02_FILE}" \
  && fa_quants=OFF \
  && native_flag=OFF \
  && if [ "${GGML_CUDA_FA_ALL_QUANTS}" = "1" ]; then fa_quants=ON; fi \
  && if [ "${GGML_NATIVE}" = "1" ]; then native_flag=ON; fi \
  && cmake \
      -S "${LLAMA_CPP_DIR}" \
      -B "${LLAMA_CPP_DIR}/build" \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DGGML_CUDA=ON \
      -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCHITECTURES}" \
      -DGGML_CUDA_FA_ALL_QUANTS="${fa_quants}" \
      -DGGML_NATIVE="${native_flag}" \
      -DLLAMA_OPENSSL=OFF \
      -DLLAMA_BUILD_SERVER=ON \
      -DLLAMA_BUILD_UI=OFF \
      -DLLAMA_USE_PREBUILT_UI=OFF \
      -DLLAMA_BUILD_TESTS=OFF \
  && export LD_LIBRARY_PATH="/usr/local/cuda/compat:${LD_LIBRARY_PATH}" \
  && cmake --build "${LLAMA_CPP_DIR}/build" --config Release -j "$(nproc)" \
      --target llama-server llama-cli llama-bench \
  && test -x "${LLAMA_CPP_DIR}/build/bin/llama-server" \
  && test -x "${LLAMA_CPP_DIR}/build/bin/llama-cli" \
  && test -x "${LLAMA_CPP_DIR}/build/bin/llama-bench"

COPY scripts/ /opt/hy3-wrapper/scripts/
RUN chmod +x /opt/hy3-wrapper/scripts/*.sh

WORKDIR /opt/hy3-wrapper
EXPOSE 8080

CMD ["/opt/hy3-wrapper/scripts/docker_entrypoint.sh"]
