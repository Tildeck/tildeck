# syntax=docker/dockerfile:1
#
# Tildeck server image. The admin panel is built here too and shipped inside
# the server image, so a deployment is one application container.
#
# Build from the repository root with the panel as a named context:
#   docker build --build-context panel=./panel -f server/Dockerfile ./server
#
# Stages:
#   panel-deps     npm ci from panel/package-lock.json
#   panel-source   panel deps + the panel source tree
#   panel-check    panel lint and type-check (scripts/verify.sh, CI)
#   panel-build    the static panel bundle
#   deps           Python dependencies from uv.lock into /opt/venv (no dev tools)
#   test           deps + dev tools + tests (scripts/verify.sh, CI)
#   runtime        the published image: code, venv, panel, non-root user
#
# The version is passed as APP_VERSION at build time from the repo-root
# VERSION file by the workflow scripts and the publish workflow.

ARG NODE_IMAGE=node:26-alpine@sha256:0b36e8c136b94cd4fcf02188228e76c31ad5872eef3fec8cbd2eee500cfd9e80
ARG PYTHON_IMAGE=python:3.14-slim@sha256:51dafde81dbdb6ebde285137a295cf18a47ca95234fe388a343719cb97305b3d
ARG UV_IMAGE=ghcr.io/astral-sh/uv:0.12.9@sha256:8b940d3a9d65bed080436972241af2e21c84b5e8c9193f7014ed71479ee795ff

FROM ${UV_IMAGE} AS uv


# --- Panel -------------------------------------------------------------------
FROM ${NODE_IMAGE} AS panel-deps
ENV NUXT_TELEMETRY_DISABLED=1 \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_FUND=false
WORKDIR /panel
COPY --from=panel package.json package-lock.json ./
# --ignore-scripts: `nuxt prepare` (postinstall) needs the source tree, which
# the source stage runs explicitly once it is present.
RUN npm ci --ignore-scripts


FROM panel-deps AS panel-source
COPY --from=panel . .
RUN npx nuxt prepare


FROM panel-source AS panel-check
RUN npm run lint && npm run typecheck


FROM panel-source AS panel-build
ARG APP_VERSION=0.0.0
ENV APP_VERSION=$APP_VERSION
RUN npm run generate


# --- Server ------------------------------------------------------------------
FROM ${PYTHON_IMAGE} AS deps

COPY --from=uv /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/opt/venv

WORKDIR /app
COPY pyproject.toml uv.lock ./
# --locked: uv.lock is the contract. The build fails when it no longer
# matches pyproject.toml (--frozen would install it without checking).
RUN uv sync --locked --no-dev


FROM deps AS test

RUN uv sync --locked
ENV PATH=/opt/venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

COPY app ./app
COPY tests ./tests
COPY openapi.json ./openapi.json

RUN groupadd --system app \
    && useradd --system --gid app --home-dir /app --shell /usr/sbin/nologin app \
    && chown -R app:app /app
USER app


FROM ${PYTHON_IMAGE} AS runtime

ENV PATH=/opt/venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PANEL_DIR=/app/panel

ARG APP_VERSION=0.0.0
ENV APP_VERSION=$APP_VERSION

WORKDIR /app
COPY --from=deps /opt/venv /opt/venv
COPY app ./app
COPY --from=panel-build /panel/.output/public ./panel

RUN groupadd --system app \
    && useradd --system --gid app --home-dir /app --shell /usr/sbin/nologin app \
    && chown -R app:app /app
USER app

EXPOSE 8080

# Readiness, not just liveness: the container is healthy only when the
# database answers. Stdlib-only probe, because slim images ship no curl.
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/api/health/ready', timeout=8)"

# The server always sits behind a TLS-terminating reverse proxy, which is the
# only thing that should reach this port. Without the proxy headers the client
# address and the https scheme would be lost.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--proxy-headers", "--forwarded-allow-ips", "*"]
