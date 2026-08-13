ARG CUDA_IMAGE=nvcr.io/nvidia/cuda:13.0.1-devel-ubuntu24.04
FROM ${CUDA_IMAGE}

ARG DS4_REF=main
ARG DS4_COMMIT=b7e9f0091139999b6c070a57590c447c5741da5c
ARG DS4_WRAPPER_REVISION=unknown
ARG BUILD_JOBS=8

COPY vendor/ds4-src/ /opt/ds4/

RUN set -eux; \
    test -f /opt/ds4/Makefile; \
    test "$(cat /opt/ds4/.pinned-commit)" = "${DS4_COMMIT}"; \
    command -v make; \
    command -v gcc; \
    command -v g++; \
    command -v nvcc; \
    make -C /opt/ds4 clean; \
    make -C /opt/ds4 cuda-spark -j"${BUILD_JOBS}"; \
    test -x /opt/ds4/ds4-server; \
    test -x /opt/ds4/ds4-bench; \
    /opt/ds4/ds4-server --help >/dev/null

COPY scripts/entrypoint.sh /opt/llm-sql-ds4/entrypoint.sh
RUN chmod 0755 /opt/llm-sql-ds4/entrypoint.sh

LABEL org.opencontainers.image.source="https://github.com/antirez/ds4" \
      org.opencontainers.image.version="${DS4_REF}" \
      org.opencontainers.image.revision="${DS4_COMMIT}" \
      io.llm-sql.wrapper.revision="${DS4_WRAPPER_REVISION}"

WORKDIR /opt/ds4
EXPOSE 8080
ENTRYPOINT ["/opt/llm-sql-ds4/entrypoint.sh"]
