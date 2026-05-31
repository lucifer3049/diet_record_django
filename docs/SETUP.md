# 環境建置（Setup）

> 回到 [README](../README.md) ｜ 相關：[docker.md](docker.md)、[commands.md](commands.md)、[developer-guide.md](developer-guide.md)

本專案採 **Docker-first**：所有相依裝在容器內，本機**不需安裝 Python、不會產生 venv**。

---

## 先決條件

| 工具 | 用途 | 備註 |
| --- | --- | --- |
| Docker Desktop | 容器執行環境（含 Compose v2） | Windows 須啟用 WSL2 backend |
| Git | 版本控制 | |

---

## Windows 使用者（重要）

Windows 上以 Git Bash 直接操作 Docker 會反覆遇到三類摩擦：路徑自動轉換、CRLF 換行讓容器內 shell 出錯、bind mount 緩慢且 `runserver` autoreload 失效。**強烈建議改用 WSL2。**

### 設定 WSL2（約五分鐘）

```powershell
# PowerShell（系統管理員）
wsl --install      # 會安裝 Ubuntu，依提示重開機
```

重開後：

1. Docker Desktop → **Settings → Resources → WSL Integration** → 勾選你的 Ubuntu distro。
2. 開啟 **Ubuntu (WSL)** 終端機，將專案放在 **Linux 原生檔案系統**：

   ```bash
   mkdir -p ~/projects && cd ~/projects
   git clone https://github.com/lucifer3049/diet_record_django.git
   cd diet_record_django
   ```

   > **關鍵**：工作目錄要在 `~/projects/...`，**不要**放在 `/mnt/c/...` 或 `/mnt/d/...`。`/mnt/*` 是掛載 Windows 磁碟，走慢路徑；Linux 原生 FS 才有接近原生速度與正常 autoreload。

進入 WSL2 後，本文件所有指令皆可直接執行，**不需** `MSYS_NO_PATHCONV`、不會有 CRLF 問題。

### 若仍堅持使用 Git Bash（不建議）

需注意兩個常見地雷：

- **路徑自動轉換**：`docker run ... -w /app` 會被 Git Bash 誤翻成 `C:/Program Files/Git/app`。解法：指令前加 `MSYS_NO_PATHCONV=1`。
- **`curl` 路徑轉換**：`curl http://localhost:8000/readyz/` 中的 `/readyz/` 也可能被轉換。同樣加 `MSYS_NO_PATHCONV=1`。
- **CRLF**：`.gitattributes` 已設 `* text=auto eol=lf` 緩解；但編輯器仍可能寫入 CRLF。

---

## 建置步驟

### 情境 A：clone 既有專案

```bash
# 1. clone
git clone https://github.com/lucifer3049/diet_record_django.git
cd diet_record_django

# 2. 建立本機 .env（compose 已注入主要變數，此檔供容器外直接執行用）
cp .env.example .env

# 3. build + 啟動
docker compose up -d --build

# 4. 套用 migration
docker compose exec web python manage.py migrate

# 5. （可選）建立管理員帳號
docker compose run --rm web python manage.py createsuperuser

# 6. 驗證
curl -i http://localhost:8000/readyz/      # Git Bash: 前面加 MSYS_NO_PATHCONV=1
```

### 情境 B：從零建立新專案

專案根目錄附有 `bootstrap.sh`，會直接寫入完整 M0 骨架（不經 `django-admin`，避免手動重塑時的人為遺漏）：

```bash
mkdir -p ~/projects/my-new-project && cd ~/projects/my-new-project
# 將 bootstrap.sh 放入此資料夾，然後：
bash bootstrap.sh
```

它會依序完成：建立目錄與所有檔案 → `uv lock` → `docker compose build` → `makemigrations` → `migrate`，最後印出驗證指令。

---

## 環境變數

`.env.example` 提供開發預設值（**勿將真實 secret 提交至版本庫**）：

```dotenv
SECRET_KEY=dev-insecure-change-me
DJANGO_DEBUG=true
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1
DATABASE_URL=postgres://nutrition:nutrition@localhost:5432/nutrition
REDIS_URL=redis://redis:6379/0
POSTGRES_DB=nutrition
POSTGRES_USER=nutrition
POSTGRES_PASSWORD=nutrition
```

| 變數 | 說明 |
| --- | --- |
| `SECRET_KEY` | Django 密鑰；prod 必須以環境變數提供且為高熵值 |
| `DJANGO_DEBUG` | 開發為 `true`，正式為 `false` |
| `DJANGO_ALLOWED_HOSTS` | 逗號分隔；prod 必填 |
| `DATABASE_URL` | PostgreSQL 連線字串 |
| `REDIS_URL` | Redis 連線字串 |

> compose 在 `web` 服務中已注入這些變數（容器內 DB host 為 `db`、Redis host 為 `redis`）。`.env` 主要供「在容器外」直接執行工具時使用。

---

## 為什麼不會產生 venv

- **安裝 uv ≠ 產生 venv**；**安裝 Python ≠ 產生 venv**。venv 只在「安裝專案相依」那一刻生成。
- `uv lock` 只做相依**解析**、寫 `uv.lock`，**不安裝** → 不產生 venv。
- 唯一一次安裝發生在 `docker compose build`，裝進**映像檔內**的 `/opt/venv`。
- `/opt/venv` 這條路徑**不在** bind mount（`.:/app`）範圍內 → 只活在 Linux 映像檔裡，永遠不會出現在 Windows 資料夾。

這是刻意設計（Dockerfile 的 `UV_PROJECT_ENVIRONMENT=/opt/venv`），用以避免「Windows binary 的 venv 被掛進 Linux 容器」這種混用災難。**因此不需、也不應在本機執行 `uv sync` 或 `pip install`。**

---

## 驗證安裝成功

```bash
curl -i http://localhost:8000/readyz/
```

- `HTTP 200` + `{"status": "ok", "checks": {"database": "ok", "cache": "ok"}}` → 成功。
- `HTTP 503` → DB 或 cache 未就緒，檢查 `docker compose ps` 容器狀態。
- `404` → URLconf 未正確載入，檢查 `config/urls.py`。

排錯細節見 [developer-guide.md 常見問題與排錯](developer-guide.md#常見問題與排錯指南)。
