# syntax=docker/dockerfile:1

ARG OPEN_WEBUI_BASE=ghcr.io/open-webui/open-webui:v0.9.4

FROM node:22-alpine3.20 AS frontend

ARG OPEN_WEBUI_REPO=https://github.com/open-webui/open-webui.git
ARG OPEN_WEBUI_REF=f51d2b026f1b0e7283b15f093412be8b67d24770

RUN apk add --no-cache git

WORKDIR /src
RUN git clone --filter=blob:none --no-checkout "${OPEN_WEBUI_REPO}" . \
	&& git checkout --detach "${OPEN_WEBUI_REF}" \
	&& test "$(git rev-parse HEAD)" = "${OPEN_WEBUI_REF}"

COPY response-performance-stats.patch /tmp/response-performance-stats.patch
RUN git apply --recount --check /tmp/response-performance-stats.patch \
	&& git apply --recount /tmp/response-performance-stats.patch

RUN npm ci --force
ENV APP_BUILD_HASH=dgx-response-stats
RUN npm run build

FROM ${OPEN_WEBUI_BASE}

COPY --from=frontend /src/build /app/build
