# AI Nutrition Advisor Platform（智慧營養師飲食健康平台）

> 結合 AI 營養分析、飲食紀錄、健康追蹤與 RAG 知識庫的健康管理平台。
> 採學習導向、可演進的工程實踐：先做出能跑的 vertical slice，再逐步硬化為 production-ready。

[![CI](https://github.com/lucifer3049/diet_record_django/actions/workflows/ci.yml/badge.svg)](https://github.com/lucifer3049/diet_record_django/actions)

---

## 目錄

- [專案目標與功能](#專案目標與功能)
- [系統架構](#系統架構)
- [技術棧](#技術棧-tech-stack)
- [專案目錄結構](#專案目錄結構)
- [開發環境需求](#開發環境需求)
- [快速啟動](#快速啟動)
- [Docker 使用方式](#docker-使用方式)
- [資料庫](#資料庫)
- [Migration 操作流程](#migration-操作流程)
- [測試](#測試)
- [程式碼品質檢查](#程式碼品質檢查)
- [常見開發流程](#常見開發流程)
- [Roadmap](#roadmap)
- [完整文件](#完整文件)

---

## 專案目標與功能

打造一套可商業化、可維護、可擴充的 AI 健康管理平台。規劃功能：

| 領域 | 功能 | 狀態 |
| --- | --- | --- |
| 使用者 | 註冊 / JWT 認證 / Profile（性別、年齡、身高、活動量、健康目標） | Profile 模型已建，JWT 規劃中（M1.3） |
| 健康追蹤 | 體重 / 體脂率 / 腰圍 紀錄、BMI 計算、趨勢分析 | 模型 + BMI 領域邏輯已建（M1.1） |
| 飲食紀錄 | 早午晚點心、食物搜尋、AI 圖片辨識 | 規劃中（M2） |
| 食物知識庫 | 衛福部 / USDA 資料、ETL 自動同步 | 規劃中（M3） |
| AI 營養分析 | LLM 分析熱量與營養素、飲食評分 | 規劃中（M4） |
| RAG 知識庫 | 向量檢索 + 引用來源 | 規劃中（M5） |

> 詳細里程碑與目前進度見 [docs/ROADMAP.md](docs/ROADMAP.md)。

---

## 系統架構

本專案採 **Modular Monolith（模組化單體）**，而非微服務——在 domain 尚未穩定、單人開發的階段，微服務是過度設計。各 Django app 維持清楚邊界，未來若有需要可沿邊界拆分。

採 **務實的 Clean Architecture / 分層架構**（非完整 Hexagonal）。四層職責：

```
┌─────────────────────────────────────────────────────┐
│  Interface（介面層）   DRF View + Serializer          │  ← HTTP I/O，薄
├─────────────────────────────────────────────────────┤
│  Application（應用層） services.py（寫）              │  ← 用例編排、交易邊界
│                        selectors.py（讀）             │
├─────────────────────────────────────────────────────┤
│  Domain（領域層）      domain.py（純函式）            │  ← 業務規則，零框架相依
│                        model 內在不變式               │
├─────────────────────────────────────────────────────┤
│  Infrastructure（基礎設施） Django ORM / DB / Cache   │  ← 框架與外部資源
└─────────────────────────────────────────────────────┘
```

**核心設計原則**：business logic 不散落在 view / serializer / signal；公式類純邏輯進 `domain.py`（可即時單元測試）；跨實體的組裝（如 BMI 需要 Profile 的身高 + HealthRecord 的體重）進 application 層的 selector。

完整架構說明與設計決策（含 trade-offs）見 [docs/architecture.md](docs/architecture.md)。

---

## 技術棧 (Tech Stack)

| 分類 | 技術 | 版本 | 備註 |
| --- | --- | --- | --- |
| 語言 | Python | 3.12 | modern typing、`StrEnum` |
| Web 框架 | Django | 5.2 LTS | 長期專案優先 LTS |
| API | Django REST Framework | 3.15 | endpoints 規劃於 M1.4 |
| 資料庫 | PostgreSQL | 16 | |
| 快取 | Redis | 7 | Django 原生 redis backend |
| DB driver | psycopg | 3.x | |
| WSGI server | gunicorn | 22 | prod；M4 接 LLM 時評估改 ASGI |
| 相依管理 | uv | latest | lock + venv + 安裝一條龍 |
| Lint / Format | Ruff | 0.6+ | 取代 Black + isort |
| 型別檢查 | mypy (strict) | 1.11+ | + django-stubs、DRF stubs |
| 測試 | pytest / pytest-django / factory_boy | — | factory_boy 用於 M1.5+ |
| 容器 | Docker / Docker Compose | — | 多階段 build |
| CI | GitHub Actions | — | ruff + mypy + migration check + pytest |

**規劃導入**（後續里程碑）：Celery + Celery Beat（M3）、向量資料庫 pgvector（M5）、Vue3 + TypeScript 前端（M1.6+）。

---

## 專案目錄結構

```
diet_record_django/
├── compose.yaml                # Docker Compose：web / db / redis
├── Dockerfile                  # 多階段 build（venv 在 /opt/venv）
├── .dockerignore
├── .gitignore  .gitattributes  # eol=lf 避免 Windows CRLF 問題
├── .env.example                # 環境變數範本（secret 不入庫）
├── pyproject.toml              # 相依 + ruff + mypy + pytest 設定
├── uv.lock                     # 鎖定相依（須入庫，保證重現）
├── manage.py
├── bootstrap.sh                # 一鍵重建 M0 骨架（新專案用）
│
├── .github/workflows/ci.yml    # CI pipeline
│
├── config/                     # Django「專案」：組態、不放 business code
│   ├── settings/
│   │   ├── base.py             # 共用設定
│   │   ├── dev.py              # 開發（DEBUG=True）
│   │   └── prod.py             # 正式（安全標頭）
│   ├── urls.py                 # root URLconf
│   ├── wsgi.py  asgi.py
│
├── core/                       # 跨領域共用碼
│   ├── healthcheck.py          # /healthz /readyz
│   └── tests.py                # health check smoke tests
│
├── apps/                       # 業務 app（modular monolith）
│   ├── accounts/               # 使用者 + Profile
│   │   ├── models.py           # User（自訂）, UserProfile
│   │   ├── admin.py
│   │   └── migrations/
│   └── health/                 # 健康指標（time-series）
│       ├── domain.py           # compute_bmi / classify_bmi（純函式）
│       ├── models.py           # HealthRecord + custom QuerySet
│       ├── admin.py
│       ├── tests.py            # 純領域單元測試
│       └── migrations/
│
└── docs/                       # 專案文件（見下方連結）
```

> `config/` 與 `apps/` 刻意分離：`config` 只管「怎麼把系統組起來」，business code 一律放 `apps/`。

---

## 開發環境需求

- **Docker Desktop**（含 Docker Compose v2）
- **Git**
- **Windows 使用者強烈建議 WSL2**：將 repo 放在 WSL2 的 Linux 檔案系統內（如 `~/projects/`），避免 Git Bash 路徑轉換、CRLF、bind mount 緩慢與 autoreload 失效等問題。詳見 [docs/setup.md](docs/setup.md#windows-使用者)。
- **不需在本機安裝 Python**：所有相依裝在容器內的 `/opt/venv`，本機不會產生 venv。

詳細安裝步驟見 [docs/setup.md](docs/setup.md)。

---

## 快速啟動

```bash
# 1. clone
git clone https://github.com/lucifer3049/diet_record_django.git
cd diet_record_django

# 2. 建立 .env（compose 已注入主要變數，此步主要供容器外直接執行用）
cp .env.example .env

# 3. build + 啟動（web / db / redis）
docker compose up -d --build

# 4. 套用 migration
docker compose exec web python manage.py migrate

# 5. 驗證（Windows Git Bash 需加 MSYS_NO_PATHCONV=1）
curl -i http://localhost:8000/readyz/
```

預期回應：`HTTP 200`，body 為 `{"status": "ok", "checks": {"database": "ok", "cache": "ok"}}`。

> 若是**全新**建立專案（非 clone），改用 `bash bootstrap.sh` 一鍵產生骨架。

---

## Docker 使用方式

| 動作 | 指令 |
| --- | --- |
| 建置並啟動 | `docker compose up -d --build` |
| 啟動（已建置） | `docker compose up -d` |
| 停止 | `docker compose down` |
| 看 log | `docker compose logs -f web` |
| 進入 web 容器 shell | `docker compose exec web bash` |
| 執行一次性指令（需 DB） | `docker compose run --rm web <cmd>` |
| 執行一次性指令（不需 DB，較快） | `docker compose run --rm --no-deps web <cmd>` |

dev 環境跑 `runserver`（autoreload）、prod 跑 `gunicorn`，同一個 image 用 command 區分。架構與每個決策的理由見 [docs/docker.md](docs/docker.md)。

---

## 資料庫

- **PostgreSQL 16**，連線字串透過 `DATABASE_URL` 環境變數注入。
- **時區**：`TIME_ZONE = "Asia/Taipei"`、`USE_TZ = True`（DB 存 UTC，顯示轉台北）。
- **交易策略**：`ATOMIC_REQUESTS = False`，改用明確的 `transaction.atomic()` 包住「真正寫 DB」的範圍（避免在呼叫 LLM 等長 I/O 時長時間握著連線與鎖）。

資料模型、ER 圖、索引策略見 [docs/database.md](docs/database.md)。

---

## Migration 操作流程

```bash
# 產生 migration（修改 model 後）
docker compose run --rm web python manage.py makemigrations

# 套用 migration
docker compose exec web python manage.py migrate

# 檢查「model 改了卻忘了產 migration」（CI 也會跑這個閘門）
docker compose run --rm web python manage.py makemigrations --check --dry-run
```

> **Migration safety**：CI 會以 `makemigrations --check` 擋下「改了 model 卻沒產生 migration」的 PR。詳見 [docs/database.md](docs/database.md#migration)。

---

## 測試

```bash
# 全部測試（需要 db + redis，勿加 --no-deps）
docker compose run --rm web pytest -q

# 只跑純領域測試（無 DB，毫秒級）
docker compose run --rm --no-deps web pytest apps/health/tests.py -q
```

測試分兩類：**純領域**（無 DB、極快，如 BMI 計算）與**整合**（標 `@pytest.mark.django_db`，如 readiness）。詳見 [docs/testing.md](docs/testing.md)。

---

## 程式碼品質檢查

推送前須通過四道閘門：

```bash
docker compose run --rm --no-deps web ruff check --fix .   # lint（自動修）
docker compose run --rm --no-deps web ruff format .         # 格式化
docker compose run --rm --no-deps web mypy .                # 型別檢查（strict）
docker compose run --rm web pytest -q                       # 測試
```

Ruff 與 mypy 的規則設定、以及為何停用某些規則（中文標點 RUF001-003、model 的 RUF012、admin 的 type-arg）見 [docs/code_quality.md](docs/code_quality.md)。

---

## 常見開發流程

```bash
# 1. 從 main 開 feature branch
git switch main && git pull
git switch -c feature/<簡述>

# 2. 開發 → 通過四道品質閘門（見上）

# 3. commit + push
git add .
git commit -m "M1.x: <簡述>"
git push -u origin <branch>

# 4. 開 PR → CI 綠燈 → review → merge
```

新增 app / model、層級放置原則、Code Review 流程見 [docs/development.md](docs/development.md) 與 [docs/developer-guide.md](docs/developer-guide.md)。

---

## Roadmap

| 里程碑 | 內容 | 狀態 |
| --- | --- | --- |
| **M0** | Walking Skeleton（容器、設定分層、健康檢查、CI） | ✅ 完成 |
| **M1** | 使用者 + 健康指標 | 🚧 進行中（M1.1 ✅） |
| **M2** | 飲食紀錄（純 CRUD） | ⬜ |
| **M3** | 食物知識庫 + ETL（單一來源、無向量） | ⬜ |
| **M4** | LLM 營養分析（無 RAG）→ 引入 `AIProvider` port | ⬜ |
| **M5** | RAG + pgvector | ⬜ |
| **M6** | 擴充 + observability + 上雲 | ⬜ |

完整里程碑拆解見 [docs/ROADMAP.md](docs/ROADMAP.md)。

---

## 完整文件

| 文件 | 內容 |
| --- | --- |
| [docs/setup.md](docs/setup.md) | 環境建置（含 Windows / WSL2） |
| [docs/architecture.md](docs/architecture.md) | 系統架構與設計決策 |
| [docs/database.md](docs/database.md) | 資料模型、ER 圖、Migration |
| [docs/api.md](docs/api.md) | API 說明（現況 + 規劃） |
| [docs/development.md](docs/development.md) | 開發流程 |
| [docs/docker.md](docs/docker.md) | Docker 指令與架構 |
| [docs/testing.md](docs/testing.md) | 測試說明 |
| [docs/code_quality.md](docs/code_quality.md) | Ruff、MyPy、品質規則 |
| [docs/deployment.md](docs/deployment.md) | 部署流程 |
| [docs/commands.md](docs/commands.md) | 所有常用指令整理 |
| [docs/developer-guide.md](docs/developer-guide.md) | 新進開發者上手指南 |
| [docs/ROADMAP.md](docs/ROADMAP.md) | 開發里程碑 |
