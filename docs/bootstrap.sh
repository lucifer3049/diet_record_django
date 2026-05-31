# 下次新建專案時直接用這兩條指令
# mkdir -p ~/projects/my-new-project && cd ~/projects/my-new-project
# 把 bootstrap.sh 放進這個資料夾，然後：
# bash bootstrap.sh

#!/usr/bin/env bash
#
# M0 Walking Skeleton — 一鍵 bootstrap
#
# 用法（在「空的」專案資料夾內）：
#   bash bootstrap.sh
#
# 設計重點：直接寫入所有檔案，不使用 django-admin startproject/startapp。
# 之前連續報錯（settings 沒拆成套件、apps.py name 沒改、MSYS 路徑轉換）
# 全部來自「手動重塑生成檔」漏片段；改成腳本直寫就完全消除這類人為遺漏。
#
set -euo pipefail

# 關閉 Git Bash(MINGW64) 的路徑自動轉換；在 WSL/Linux 上設這個無影響。
export MSYS_NO_PATHCONV=1

UV_IMAGE="ghcr.io/astral-sh/uv:python3.12-bookworm-slim"

echo "==> 1/5 建立目錄"
mkdir -p config/settings core apps/accounts/migrations docs

echo "==> 2/5 寫入所有檔案"

# ---------- meta ----------
cat > pyproject.toml << 'EOF'
[project]
name = "nutrition-advisor"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
    "django>=5.2,<5.3",
    "djangorestframework>=3.15",
    "django-environ>=0.11",
    "psycopg[binary]>=3.2",
    "redis>=5.0",
    "gunicorn>=22.0",
]

[dependency-groups]
dev = [
    "pytest>=8.0",
    "pytest-django>=4.8",
    "factory-boy>=3.3",
    "ruff>=0.6",
    "mypy>=1.11",
    "django-stubs[compatible-mypy]>=5.0",
    "djangorestframework-stubs>=3.15",
]

[tool.uv]
package = false

[tool.ruff]
target-version = "py312"
line-length = 100
extend-exclude = ["**/migrations/**"]  
[tool.ruff.lint]
select = ["E", "F", "I", "UP", "B", "DJ", "RUF"]
ignore = ["RUF001", "RUF002", "RUF003"]  
[tool.ruff.lint.per-file-ignores]
"config/settings/*" = ["F403", "F405"] 

[tool.pytest.ini_options]
DJANGO_SETTINGS_MODULE = "config.settings.dev"
python_files = ["test_*.py", "*_test.py", "tests.py"]

[tool.mypy]
plugins = ["mypy_django_plugin.main"]
strict = true
exclude = ["migrations/", "config/settings/"]
[tool.django-stubs]
django_settings_module = "config.settings.dev"

[[tool.mypy.overrides]]
module = "environ.*"
ignore_missing_imports = true
django_settings_module = "config.settings.dev"
EOF

cat > Dockerfile << 'EOF'
# syntax=docker/dockerfile:1
FROM python:3.12-slim AS base
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/venv
# uv 二進位檔（正式環境請改釘版本，例如 uv:0.5.x，勿用 latest）
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
EOF

cat > compose.yaml << 'EOF'
services:
  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-nutrition}
      POSTGRES_USER: ${POSTGRES_USER:-nutrition}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-nutrition}
    volumes: [pgdata:/var/lib/postgresql/data]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-nutrition}"]
      interval: 5s
      timeout: 3s
      retries: 5
    ports: ["5432:5432"]

  redis:
    image: redis:7-alpine
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
    ports: ["6379:6379"]

  web:
    build: .
    command: python manage.py runserver 0.0.0.0:8000
    environment:
      DJANGO_SETTINGS_MODULE: config.settings.dev
      SECRET_KEY: ${SECRET_KEY:-dev-insecure-change-me}
      DATABASE_URL: postgres://${POSTGRES_USER:-nutrition}:${POSTGRES_PASSWORD:-nutrition}@db:5432/${POSTGRES_DB:-nutrition}
      REDIS_URL: redis://redis:6379/0
    volumes: [".:/app"]
    ports: ["8000:8000"]
    depends_on:
      db: { condition: service_healthy }
      redis: { condition: service_healthy }

volumes:
  pgdata:
EOF

cat > .dockerignore << 'EOF'
.venv
__pycache__
*.pyc
.git
.env
staticfiles
.pytest_cache
.mypy_cache
.ruff_cache
EOF

cat > .gitignore << 'EOF'
.venv/
__pycache__/
*.pyc
.env
staticfiles/
.pytest_cache/
.mypy_cache/
.ruff_cache/
EOF

cat > .env.example << 'EOF'
SECRET_KEY=dev-insecure-change-me
DJANGO_DEBUG=true
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1
DATABASE_URL=postgres://nutrition:nutrition@localhost:5432/nutrition
REDIS_URL=redis://localhost:6379/0
POSTGRES_DB=nutrition
POSTGRES_USER=nutrition
POSTGRES_PASSWORD=nutrition
EOF

cat > .gitattributes << 'EOF'
* text=auto eol=lf
EOF

# ---------- config 套件 ----------
: > config/__init__.py
: > config/settings/__init__.py

cat > config/settings/base.py << 'EOF'
from __future__ import annotations

from pathlib import Path

import environ

BASE_DIR = Path(__file__).resolve().parent.parent.parent

env = environ.Env(DJANGO_DEBUG=(bool, False))
env_file = BASE_DIR / ".env"
if env_file.exists():
    environ.Env.read_env(env_file)

SECRET_KEY = env("SECRET_KEY")
DEBUG = env("DJANGO_DEBUG")
ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS", default=[])

DJANGO_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
]
THIRD_PARTY_APPS = ["rest_framework"]
LOCAL_APPS = ["apps.accounts"]
INSTALLED_APPS = DJANGO_APPS + THIRD_PARTY_APPS + LOCAL_APPS

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"
ASGI_APPLICATION = "config.asgi.application"

TEMPLATES = [{
    "BACKEND": "django.template.backends.django.DjangoTemplates",
    "DIRS": [],
    "APP_DIRS": True,
    "OPTIONS": {"context_processors": [
        "django.template.context_processors.request",
        "django.contrib.auth.context_processors.auth",
        "django.contrib.messages.context_processors.messages",
    ]},
}]

DATABASES = {"default": env.db("DATABASE_URL")}
DATABASES["default"]["ATOMIC_REQUESTS"] = False

CACHES = {"default": {
    "BACKEND": "django.core.cache.backends.redis.RedisCache",
    "LOCATION": env("REDIS_URL", default="redis://localhost:6379/0"),
}}

AUTH_USER_MODEL = "accounts.User"

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "Asia/Taipei"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
EOF

cat > config/settings/dev.py << 'EOF'
from .base import *  # noqa: F403

DEBUG = True
ALLOWED_HOSTS = ["*"]
EOF

cat > config/settings/prod.py << 'EOF'
from .base import *  # noqa: F403

DEBUG = False
ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS")

SECURE_SSL_REDIRECT = env.bool("DJANGO_SSL_REDIRECT", default=True)
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_HSTS_SECONDS = env.int("DJANGO_HSTS_SECONDS", default=60 * 60 * 24 * 30)
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
EOF

cat > config/urls.py << 'EOF'
from django.contrib import admin
from django.urls import path

from core.healthcheck import liveness, readiness

urlpatterns = [
    path("admin/", admin.site.urls),
    path("healthz/", liveness),
    path("readyz/", readiness),
]
EOF

cat > config/wsgi.py << 'EOF'
import os

from django.core.wsgi import get_wsgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.prod")
application = get_wsgi_application()
EOF

cat > config/asgi.py << 'EOF'
import os

from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.prod")
application = get_asgi_application()
EOF

cat > manage.py << 'EOF'
#!/usr/bin/env python
import os
import sys


def main() -> None:
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings.dev")
    from django.core.management import execute_from_command_line

    execute_from_command_line(sys.argv)


if __name__ == "__main__":
    main()
EOF

# ---------- core ----------
: > core/__init__.py

cat > core/healthcheck.py << 'EOF'
from __future__ import annotations

from django.core.cache import cache
from django.db import connection
from django.http import HttpRequest, JsonResponse


def liveness(request: HttpRequest) -> JsonResponse:
    """程序活著就回 200（k8s liveness probe 用）。"""
    return JsonResponse({"status": "ok"})


def readiness(request: HttpRequest) -> JsonResponse:
    """相依資源(DB / cache)可用才回 200，否則 503（readiness probe 用）。"""
    checks: dict[str, str] = {}
    healthy = True
    try:
        with connection.cursor() as cur:
            cur.execute("SELECT 1")
        checks["database"] = "ok"
    except Exception:  # noqa: BLE001
        checks["database"] = "error"
        healthy = False
    try:
        cache.set("__readiness__", "1", timeout=5)
        ok = cache.get("__readiness__") == "1"
        checks["cache"] = "ok" if ok else "error"
        healthy = healthy and ok
    except Exception:  # noqa: BLE001
        checks["cache"] = "error"
        healthy = False
    return JsonResponse(
        {"status": "ok" if healthy else "degraded", "checks": checks},
        status=200 if healthy else 503,
    )
EOF

# ---------- apps/accounts ----------
: > apps/__init__.py
: > apps/accounts/__init__.py
: > apps/accounts/migrations/__init__.py

cat > apps/accounts/apps.py << 'EOF'
from django.apps import AppConfig


class AccountsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.accounts"
    label = "accounts"
EOF

cat > apps/accounts/models.py << 'EOF'
from django.contrib.auth.models import AbstractUser


class User(AbstractUser):
    """先建立自訂 User 以鎖定 AUTH_USER_MODEL；M1 再擴充 profile 欄位。"""
EOF

cat > apps/accounts/admin.py << 'EOF'
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import User

admin.site.register(User, UserAdmin)
EOF

echo "==> 3/5 產生 uv.lock（容器解析相依，不在 host 產生 venv）"
docker run --rm -v "${PWD}:/app" -w /app "$UV_IMAGE" uv lock

echo "==> 4/5 build image"
docker compose build

echo "==> 5/5 makemigrations + migrate"
docker compose run --rm --no-deps web python manage.py makemigrations accounts
docker compose up -d
docker compose exec web python manage.py migrate

echo ""
echo "完成。驗證 readiness："
echo "    MSYS_NO_PATHCONV=1 curl -i http://localhost:8000/readyz/"
echo "預期：HTTP 200，且 checks 內 database / cache 皆為 ok"
