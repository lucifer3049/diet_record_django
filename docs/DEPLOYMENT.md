# 部署流程（Deployment）

> 回到 [README](../README.md) ｜ 相關：[docker.md](docker.md)、[code_quality.md](code_quality.md)、[ROADMAP.md](ROADMAP.md)

> **現況**：專案目前尚未部署至雲端（上雲規劃於 **M6**）。本文件涵蓋：已就緒的 prod 設定、CI pipeline 現況、以及雲端部署的規劃方向。

---

## 1. CI Pipeline（已實作）

`.github/workflows/ci.yml`，於 push 至 `main` 與所有 PR 觸發。

```
push / PR
   │
   ▼
┌─────────────────────────────────────────────┐
│ job: quality (ubuntu-latest)                 │
│   services: postgres:16 + redis:7 (healthy)  │
│                                              │
│   1. checkout                                │
│   2. setup-uv (cache)                        │
│   3. uv sync --frozen                        │
│   4. ruff check       ← lint                 │
│   5. ruff format --check  ← 格式漂移          │
│   6. mypy             ← 型別（strict）        │
│   7. makemigrations --check  ← migration 安全 │
│   8. pytest           ← 測試                  │
└─────────────────────────────────────────────┘
   │ 全綠
   ▼
可合併 / 可部署
```

**設計重點**：

- service container（postgres + redis）+ healthcheck，讓 pytest 與 readiness 測試有真實相依可打，避免 flaky。
- 全程使用 uv，依 `uv.lock` 安裝，保證 CI 與本機一致（消除「我這邊會過」）。
- `makemigrations --check` 作為 migration 安全閘門。

CI 各步驟細節見 [code_quality.md](code_quality.md#5-ci-中的品質檢查)。

---

## 2. Production 設定（已就緒）

`config/settings/prod.py` 已具備安全基線：

```python
DEBUG = False
ALLOWED_HOSTS = env.list("DJANGO_ALLOWED_HOSTS")   # 必填，無預設

SECURE_SSL_REDIRECT = env.bool("DJANGO_SSL_REDIRECT", default=True)
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
SECURE_HSTS_SECONDS = env.int("DJANGO_HSTS_SECONDS", default=60 * 60 * 24 * 30)
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
```

prod 以 **gunicorn**（WSGI）啟動，環境變數驅動，所有 secret 由外部注入（**絕不寫死**）。

> **WSGI vs ASGI**：M0 先用 gunicorn（WSGI）最少變數。M4 接 LLM 需要 async 時，再評估改 ASGI（uvicorn）——屆時需注意 Django ORM 的 async 限制。

### 部署前檢查

```bash
# Django 內建部署檢查（檢查安全設定）
docker compose run --rm web python manage.py check --deploy

# 收集靜態檔（prod）
docker compose run --rm web python manage.py collectstatic --noinput
```

---

## 3. 雲端部署規劃（M6）

依專案 spec，目標為中小型 SaaS，規劃選型 **AWS**（生態系成熟、Django 部署便利、未來擴展不需重做架構）：

| 元件 | AWS 服務（規劃） | 用途 |
| --- | --- | --- |
| 容器執行 | ECS Fargate | 跑 web / worker 容器 |
| 資料庫 | RDS PostgreSQL | 取代 compose 的 db |
| 快取 | ElastiCache Redis | 取代 compose 的 redis |
| 物件儲存 | S3 | 圖片與檔案（M2 飲食圖片辨識） |
| 容器映像庫 | ECR | 存放 Docker image |
| 監控 | CloudWatch | log / metrics |

> 此為規劃，尚未實作。實作時將補上 IaC（如 Terraform）與部署腳本。

---

## 4. Zero-downtime 與部署風險（演進原則）

正式上線後須遵循：

| 主題 | 原則 |
| --- | --- |
| **Migration 安全** | 加欄位給 default/null；改/刪欄位分多次部署（先相容並存再清理）；大表用 `CREATE INDEX CONCURRENTLY`。見 [database.md](database.md#migration-安全演進原則後續里程碑) |
| **Backward compatibility** | API 變更採加法優先；破壞性變更走版本化 |
| **Health probe** | 部署平台以 `/healthz`（liveness）與 `/readyz`（readiness）判斷 pod 狀態，rolling update 才安全 |
| **連線池** | prod 評估 PgBouncer 或 Django `CONN_MAX_AGE`，避免連線耗盡（與「窄交易」設計相輔） |
| **Secret 管理** | 使用 Secrets Manager / SSM Parameter Store，不入庫、不寫死 |
| **可觀測性** | M6 導入 structured logging + tracing + metrics（Prometheus / Grafana 方向） |

---

## 5. 規劃中的 CD（M6）

CI 綠燈後的後續流程（規劃）：

```
CI 綠燈 → build Docker image → push ECR → deploy ECS（rolling update）
                                              │
                                  readiness probe 確認新版健康後切流量
```

實作時將於 `ci.yml` 後增加 `deploy` job（限 `main` 分支、需 environment approval）。
