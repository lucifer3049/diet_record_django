# API 說明

> 回到 [README](../README.md) ｜ 相關：[architecture.md](architecture.md)、[database.md](database.md)

> **現況說明**：目前（M0 + M1.1）僅實作健康檢查端點與 Django admin。完整 REST API（profile、health records、trend）規劃於 **M1.4**，JWT 認證規劃於 **M1.3**。本文件明確標示各端點狀態，避免將規劃當現況。

---

## 1. 現有端點

| 方法 | 路徑 | 用途 | 認證 | 狀態 |
| --- | --- | --- | --- | --- |
| GET | `/healthz/` | Liveness probe | 無 | ✅ |
| GET | `/readyz/` | Readiness probe（DB + cache） | 無 | ✅ |
| — | `/admin/` | Django 管理後台 | Session | ✅ |

### `GET /healthz/`（Liveness）

程序活著就回 200，**不檢查任何外部相依**。供 k8s liveness probe 使用——失敗代表程序壞了，應重啟容器。

**Response `200 OK`**
```json
{ "status": "ok" }
```

範例：
```bash
curl -i http://localhost:8000/healthz/
```

### `GET /readyz/`（Readiness）

檢查 DB 與 cache 是否可用。供 k8s readiness probe 使用——失敗代表暫時無法服務流量（應移出 load balancer），但**不該重啟**。

**Response `200 OK`**（全部健康）
```json
{
  "status": "ok",
  "checks": { "database": "ok", "cache": "ok" }
}
```

**Response `503 Service Unavailable`**（任一相依異常）
```json
{
  "status": "degraded",
  "checks": { "database": "ok", "cache": "error" }
}
```

範例：
```bash
curl -i http://localhost:8000/readyz/
```

> **為何區分 liveness / readiness**：混為一談會在 DB 短暫抖動時把健康的 pod 重啟掉。liveness 失敗 → 重啟；readiness 失敗 → 暫時移出流量。詳見 [architecture.md](architecture.md) 與 [deployment.md](deployment.md)。

---

## 2. 規劃中的 REST API（M1.3 / M1.4）

以下為規劃設計，**尚未實作**。實作時將以 DRF 提供，並產出 OpenAPI 規格。

### 認證（M1.3）

採 JWT（SimpleJWT），access + refresh token：

| 方法 | 路徑（規劃） | 用途 |
| --- | --- | --- |
| POST | `/api/auth/register/` | 註冊（顯式建立 User + Profile，不用 signal） |
| POST | `/api/auth/token/` | 登入，取得 access + refresh |
| POST | `/api/auth/token/refresh/` | 以 refresh 換新 access |

### Profile（M1.4）

| 方法 | 路徑（規劃） | 用途 |
| --- | --- | --- |
| GET | `/api/profile/` | 取得自己的 profile（含計算出的 age） |
| PATCH | `/api/profile/` | 更新 profile |

### Health Records（M1.4）

| 方法 | 路徑（規劃） | 用途 |
| --- | --- | --- |
| GET | `/api/health/records/` | 列出自己的量測紀錄（分頁、時間排序） |
| POST | `/api/health/records/` | 新增一筆量測（經 service，含驗證 + 窄交易） |
| GET | `/api/health/bmi/` | 取得最新 BMI（selector 跨 Profile + Record 組裝） |
| GET | `/api/health/trend/` | 體重 / 體脂趨勢資料 |

---

## 3. API 設計原則（實作時遵循）

- **View 薄**：使用 CBV / generics，view 只負責 HTTP I/O，呼叫 application 層（service / selector），**不放 business logic**。
- **Serializer 純 I/O**：只做欄位驗證與序列化，不放業務規則。
- **寫入走 service**：`POST` 類操作呼叫 `services.py`，由 service 控制驗證與交易邊界。
- **讀取走 selector**：`GET` 類操作呼叫 `selectors.py`，集中查詢與組裝（含 `select_related` / `prefetch_related` 防 N+1）。
- **型別化**：request / response 以 typed serializer 定義，確保 schema 一致性。
- **錯誤格式統一**：規劃統一的 error response 結構（code / message / detail）。

### 規劃的回應契約範例（BMI）

```jsonc
// GET /api/health/bmi/  →  200
{
  "bmi": 24.2,
  "category": "overweight",     // 對應 domain.BMICategory（台灣國健署切點）
  "based_on": {
    "weight_kg": 70.0,
    "height_cm": 170.0,
    "recorded_at": "2026-05-31T08:00:00+08:00"
  }
}
```

---

## 4. OpenAPI / 文件化（規劃）

M1.4 起評估導入 `drf-spectacular` 自動產生 OpenAPI 3 規格與 Swagger UI，端點為 `/api/schema/` 與 `/api/docs/`。屆時本文件將連結至自動產生的互動式文件。
