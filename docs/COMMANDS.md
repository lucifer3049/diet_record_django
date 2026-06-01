# 常用指令整理（Commands）

> 回到 [README](../README.md) ｜ 相關：[SETUP.md](SETUP.md)、[DOCKER.md](DOCKER.md)、[DEVELOPMENT.md](DEVELOPMENT.md)

本文件整理開發全程會用到的終端機指令，依分類列出。每個指令含：**用途**、**使用情境**、**範例**。

> **Windows Git Bash 提醒**：含路徑的指令（特別是 `curl`）可能被 MSYS 路徑轉換干擾，前面加 `MSYS_NO_PATHCONV=1`。建議改用 WSL2 免除此問題（見 [setup.md](setup.md#windows-使用者)）。

---

## 目錄

[Git](#git) ｜ [Docker](#docker) ｜ [Docker Compose](#docker-compose) ｜ [uv](#uv) ｜ [Django](#django) ｜ [PostgreSQL](#postgresql) ｜ [Migration](#migration) ｜ [Superuser](#superuser) ｜ [Testing / Pytest](#testing--pytest) ｜ [Ruff](#ruff) ｜ [MyPy](#mypy) ｜ [Debug](#debug) ｜ [Production](#production)

---

## Git

### `git switch -c <branch>`
- **用途**：建立並切換到新 branch。
- **情境**：開始一個新功能 / 里程碑時。
- **範例**：`git switch -c feature/2026_05_31_專案開發第一步`

### `git switch main && git pull`
- **用途**：切回 main 並同步遠端最新。
- **情境**：開新 branch 前先同步。
- **範例**：`git switch main && git pull`

### `git add . && git commit -m "..."`
- **用途**：暫存並提交變更。
- **情境**：完成一個小段落。
- **範例**：`git commit -m "M1.1: add HealthRecord model and BMI domain"`

### `git push -u origin <branch>`
- **用途**：推送 branch 並設定上游追蹤。
- **情境**：首次推送某 branch。
- **範例**：`git push -u origin feature/...`

### `git pull origin main --allow-unrelated-histories`
- **用途**：合併「無共同祖先」的歷史。
- **情境**：本機已有 commit，遠端 repo 建立時自動初始化了檔案（README/.gitignore），導致 push 被拒（`fetch first`）。
- **範例**：`git pull origin main --allow-unrelated-histories`
- **備註**：之後 `git push -u origin main`；若跳進 vim，按 `Esc` → `:wq` → Enter。

### `git status` / `git log --oneline`
- **用途**：檢視工作區狀態 / 提交歷史。
- **情境**：合併衝突後確認、查最近提交。
- **範例**：`git log --oneline -10`

---

## Docker

### `docker run --rm -v "${PWD}:/app" -w /app <image> <cmd>`
- **用途**：一次性容器執行指令（不經 compose）。
- **情境**：尚無 `uv.lock`、需用 uv 容器先產生 lock。
- **範例**：`MSYS_NO_PATHCONV=1 docker run --rm -v "${PWD}:/app" -w /app ghcr.io/astral-sh/uv:python3.12-bookworm-slim uv lock`

### `docker system prune`
- **用途**：清理未使用的容器 / 網路 / 映像檔。
- **情境**：磁碟空間不足。
- **範例**：`docker system prune`

---

## Docker Compose

### `docker compose up -d --build`
- **用途**：建置並在背景啟動所有服務。
- **情境**：首次啟動、或 Dockerfile / 相依變更後。
- **範例**：`docker compose up -d --build`

### `docker compose up -d`
- **用途**：啟動（已建置）。
- **情境**：日常開工。
- **範例**：`docker compose up -d`

### `docker compose down` / `down -v`
- **用途**：停止並移除容器（`-v` 連 volume 一起，會清空 DB）。
- **情境**：收工 / 重置環境。
- **範例**：`docker compose down`

### `docker compose ps`
- **用途**：檢視容器狀態與健康度。
- **情境**：排查啟動問題。
- **範例**：`docker compose ps`

### `docker compose logs -f web`
- **用途**：追蹤服務 log。
- **情境**：debug 執行期錯誤。
- **範例**：`docker compose logs -f web`

### `docker compose exec <svc> <cmd>`
- **用途**：在**執行中**的容器內執行指令。
- **情境**：migrate、進 shell、連 DB。
- **範例**：`docker compose exec web python manage.py migrate`

### `docker compose run --rm web <cmd>`
- **用途**：起一個一次性容器執行指令（會帶起相依服務），結束即移除。
- **情境**：需要 DB 的操作（測試、makemigrations 等）。
- **範例**：`docker compose run --rm web pytest -q`

### `docker compose run --rm --no-deps web <cmd>`
- **用途**：同上但**不啟動相依服務**，較快。
- **情境**：不需 DB 的工具（ruff、mypy）。
- **範例**：`docker compose run --rm --no-deps web ruff check .`

---

## uv

### `uv lock`
- **用途**：解析相依並產生 / 更新 `uv.lock`（不安裝）。
- **情境**：新增 / 變更 `pyproject.toml` 相依後；Docker build 需要 lock 才能進行。
- **範例**：`MSYS_NO_PATHCONV=1 docker run --rm -v "${PWD}:/app" -w /app ghcr.io/astral-sh/uv:python3.12-bookworm-slim uv lock`

### `uv sync --frozen`
- **用途**：嚴格依 `uv.lock` 安裝相依（不更新 lock）。
- **情境**：Dockerfile / CI 內安裝；保證重現性。
- **範例**：（Dockerfile 內）`uv sync --frozen --no-install-project`

> **不要**在本機（Windows）直接 `uv sync`——相依屬於容器，本機不需 venv（見 [setup.md](setup.md#為什麼不會產生-venv)）。

---

## Django

### `python manage.py runserver 0.0.0.0:8000`
- **用途**：開發伺服器（autoreload）。
- **情境**：dev 環境（compose 的 web command 已設定，通常不手動跑）。
- **範例**：`docker compose up -d`（自動以此啟動）

### `python manage.py shell`
- **用途**：進入 Django ORM 互動式 shell。
- **情境**：手動查資料、驗證 queryset。
- **範例**：`docker compose run --rm web python manage.py shell`

### `python manage.py check --deploy`
- **用途**：部署前安全設定檢查。
- **情境**：上線前。
- **範例**：`docker compose run --rm web python manage.py check --deploy`

### `python manage.py collectstatic --noinput`
- **用途**：收集靜態檔到 `STATIC_ROOT`。
- **情境**：prod 部署。
- **範例**：`docker compose run --rm web python manage.py collectstatic --noinput`

---

## PostgreSQL

### `docker compose exec db psql -U nutrition -d nutrition`
- **用途**：進入 psql 互動介面。
- **情境**：手動下 SQL、檢查資料。
- **範例**：同上

### `... psql ... -c "\dt"`
- **用途**：列出所有資料表。
- **情境**：確認 migration 是否建表。
- **範例**：`docker compose exec db psql -U nutrition -d nutrition -c "\dt"`

### `... psql ... -c "<SQL>"`
- **用途**：執行單條 SQL。
- **情境**：快速查詢 / 檢查。
- **範例**：`docker compose exec db psql -U nutrition -d nutrition -c "SELECT count(*) FROM health_healthrecord;"`

---

## Migration

### `python manage.py makemigrations`
- **用途**：依 model 變更產生 migration 檔。
- **情境**：修改 / 新增 model 後。
- **範例**：`docker compose run --rm web python manage.py makemigrations`

### `python manage.py makemigrations <app>`
- **用途**：只針對特定 app 產生。
- **情境**：聚焦單一 app。
- **範例**：`docker compose run --rm web python manage.py makemigrations health`

### `python manage.py migrate`
- **用途**：套用 migration 到資料庫。
- **情境**：產生 migration 後、或 clone 後初次啟動。
- **範例**：`docker compose exec web python manage.py migrate`

### `python manage.py makemigrations --check --dry-run`
- **用途**：檢查是否有「未產生的 migration」，不實際寫檔。
- **情境**：CI 閘門、commit 前自我檢查。
- **範例**：`docker compose run --rm web python manage.py makemigrations --check --dry-run`

### `python manage.py showmigrations`
- **用途**：顯示各 app 的 migration 套用狀態。
- **情境**：排查 migration 問題。
- **範例**：`docker compose run --rm web python manage.py showmigrations`

---

## Superuser

### `python manage.py createsuperuser`
- **用途**：建立管理員帳號（可登入 `/admin/`）。
- **情境**：初次設定、需要後台操作資料。
- **範例**：`docker compose run --rm web python manage.py createsuperuser`
- **備註**：依提示輸入 username / email / password。

---

## Testing / Pytest

### `pytest -q`
- **用途**：執行全部測試（精簡輸出）。
- **情境**：推送前第四道閘門。
- **範例**：`docker compose run --rm web pytest -q`

### `pytest <path> -q`
- **用途**：執行特定路徑的測試。
- **情境**：只測純領域（無 DB）以求快。
- **範例**：`docker compose run --rm --no-deps web pytest apps/health/tests.py -q`

### `pytest <path>::<func>`
- **用途**：執行單一測試函式。
- **情境**：聚焦 debug 某個失敗測試。
- **範例**：`docker compose run --rm web pytest apps/health/tests.py::test_compute_bmi_basic`

### `pytest -x` / `pytest -v`
- **用途**：遇第一個失敗即停 / 詳細輸出。
- **情境**：快速定位 / 看細節。
- **範例**：`docker compose run --rm web pytest -x`

---

## Ruff

### `ruff check .`
- **用途**：Lint 檢查（不修改）。
- **情境**：第一道閘門、CI。
- **範例**：`docker compose run --rm --no-deps web ruff check .`

### `ruff check --fix .`
- **用途**：Lint 並自動修可修項（import 排序、未使用 import 等）。
- **情境**：開發中快速清理。
- **範例**：`docker compose run --rm --no-deps web ruff check --fix .`

### `ruff format .`
- **用途**：格式化（換行、空格）。
- **情境**：第二道閘門。
- **範例**：`docker compose run --rm --no-deps web ruff format .`

### `ruff format --check .`
- **用途**：只檢查格式是否符合，不修改。
- **情境**：CI（擋格式漂移）。
- **範例**：`docker compose run --rm --no-deps web ruff format --check .`

---

## MyPy

### `mypy .`
- **用途**：靜態型別檢查（strict）。
- **情境**：第三道閘門、CI。
- **範例**：`docker compose run --rm --no-deps web mypy .`
- **備註**：`exclude` 對命令列明確路徑無效，故以 per-module override 處理第三方無 stub 套件（見 [code_quality.md](code_quality.md#4-mypy-設定pyprojecttoml)）。

---

## Debug

### `docker compose logs -f web`
- **用途**：即時追蹤應用 log。
- **情境**：500 錯誤、啟動失敗。
- **範例**：`docker compose logs -f web`

### `docker compose exec web bash`
- **用途**：進入執行中容器的 shell。
- **情境**：檢查檔案、手動執行指令、確認環境變數。
- **範例**：`docker compose exec web bash`

### `curl -i http://localhost:8000/readyz/`
- **用途**：驗證服務與相依健康。
- **情境**：確認啟動成功、排查 DB/cache 問題。
- **範例**：`MSYS_NO_PATHCONV=1 curl -i http://localhost:8000/readyz/`

### `docker compose ps`
- **用途**：查看容器健康狀態（healthy / starting）。
- **情境**：web 起不來時先看 db/redis 是否 healthy。
- **範例**：`docker compose ps`

---

## Production

### `python manage.py check --deploy`
- **用途**：檢查 prod 安全設定缺漏。
- **情境**：上線前。
- **範例**：`docker compose run --rm web python manage.py check --deploy`

### `gunicorn config.wsgi:application --bind 0.0.0.0:8000 --workers 3`
- **用途**：以 WSGI server 啟動（prod）。
- **情境**：正式環境（Dockerfile 的預設 CMD）。
- **範例**：（容器 CMD，通常由平台啟動）

### `python manage.py collectstatic --noinput`
- **用途**：收集靜態檔。
- **情境**：prod 部署流程一環。
- **範例**：`docker compose run --rm web python manage.py collectstatic --noinput`
