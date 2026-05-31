# syntax=docker/dockerfile:1
FROM python:3.12-slim AS base
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/venv
# 正式環境請釘住版本
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/  
WORKDIR /app

FROM base AS deps
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project

FROM base AS runtime
RUN groupadd -r app && useradd -r -g app app
COPY --from=deps /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY . .
USER app
EXPOSE 8000
CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "3"]