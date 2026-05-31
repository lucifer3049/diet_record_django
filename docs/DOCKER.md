# Docker 指令與架構

> 回到 [README](../README.md) ｜ 相關：[setup.md](setup.md)、[commands.md](commands.md)、[deployment.md](deployment.md)

---

## 1. 服務架構（compose）

```
┌──────────────────────────────────────────────────┐
│  docker compose（開發環境）                         │
│                                                    │
│   ┌─────────┐   depends_on(healthy)   ┌─────────┐  │
│   │  web    │ ───────────────────────▶│  db     │  │
│   │ Django  │                         │ Postgres│  │
│   │ :8000   │ ───────────────────────▶│ :5432   │  │
│   └─────────┘                         └─────────┘  │
│       │ depends_on(healthy)           ┌─────────┐  │
│       └──────────────────────────────▶│  redis  │  │
│                                       │ :6379   │  │
│   volume: .:/app（原始碼掛載）          └─────────┘  │
│   volume: pgdata（DB 持久化）                        │
└──────────────────────────────────────────────────┘
```

| 服務 | 映像檔 | 用途 | 對外埠 |
| --- | --- | --- | --- |
| `web` | 自建（Dockerfile） | Django 應用 | 8000 |
| `db` | postgres:16-alpine | 資料庫 | 5432 |
| `redis` | redis:7-alpine | 快取 | 6379 |

**關鍵設計**：

- `depends_on` 搭配 `condition: service_healthy` + 各服務 healthcheck，讓 `web` 等到 db/redis **真正 ready** 才啟動（而非只等容器 started）。這是啟動順序的正解。
- 容器內服務名即 DNS：`web` 連 DB 用 host `db`、連 Redis 用 host `redis`。
- dev 用 `runserver`（autoreload）、prod 用 `gunicorn`，**同一個 image** 以 command 區分。

---

## 2. 多階段 Dockerfile

```dockerfile
# syntax=docker/dockerfile:1
FROM python:3.12-slim AS base
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/venv
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
```

### 為什麼這樣設計

| 決策 | 理由 |
| --- | --- |
| **多階段 + cache mount** | 相依層被 cache，改 code 不會重裝套件，build 快 |
| **venv 在 `/opt/venv`（不在 `/app`）** | dev 用 `.:/app` 掛載會蓋掉 `/app` 內容；venv 在 `/opt/venv` 才不會被掛載覆蓋、相依性才活著。也因此本機不會產生 venv |
| **非 root 執行**（`USER app`） | 安全基本盤 |
| **`uv sync --frozen`** | 嚴格依 `uv.lock` 安裝，保證 CI / 本機 / 正式一致 |
| **CMD 用 gunicorn (WSGI)** | M0 先 WSGI 最少變數；M4 接 LLM 需 async 時再評估改 ASGI/uvicorn |

> ⚠️ Dockerfile **不支援指令行尾註解**（`#` 之後會被當參數）。`COPY --from=...uv... /uv /uvx /bin/` 這行的說明須獨立成行，否則 build 失敗。

---

## 3. 常用 Docker / Compose 指令

### 生命週期

```bash
docker compose up -d --build     # 建置並啟動（背景）
docker compose up -d             # 啟動（已建置）
docker compose build             # 只建置
docker compose down              # 停止並移除容器（保留 volume）
docker compose down -v           # 停止並移除容器 + volume（清空 DB！）
docker compose ps                # 容器狀態
docker compose restart web       # 重啟單一服務
```

### Log 與除錯

```bash
docker compose logs -f web       # 追蹤 web log
docker compose logs --tail=100 db
docker compose exec web bash     # 進入執行中的 web 容器
docker compose exec db psql -U nutrition -d nutrition
```

### 執行一次性指令

```bash
# 需要 DB（如測試、migrate）→ 不加 --no-deps，會自動帶起 db/redis
docker compose run --rm web pytest -q

# 不需要 DB（如 lint、型別檢查）→ 加 --no-deps，更快
docker compose run --rm --no-deps web ruff check .
docker compose run --rm --no-deps web mypy .
```

| 旗標 | 意義 |
| --- | --- |
| `--rm` | 執行完移除容器，不留垃圾 |
| `--no-deps` | 不啟動相依服務（db/redis），純執行不需 DB 的工具時用 |

### 清理

```bash
docker compose down --rmi local        # 移除本專案自建映像檔
docker system prune                    # 清理未使用的容器 / 網路 / 映像檔
docker volume rm diet_record_django_pgdata   # 移除 DB volume（謹慎）
```

---

## 4. dev vs prod 差異

| 項目 | dev | prod |
| --- | --- | --- |
| settings | `config.settings.dev` | `config.settings.prod` |
| 啟動指令 | `runserver`（autoreload） | `gunicorn`（多 worker） |
| `DEBUG` | True | False |
| 原始碼掛載 | `.:/app`（即時反映） | 不掛載（COPY 進 image） |
| 安全標頭 | 關 | 開（HSTS、SSL redirect、secure cookie） |

prod 部署細節見 [deployment.md](deployment.md)。
