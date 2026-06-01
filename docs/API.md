# API 說明

> 回到 [README](../README.md) ｜ 相關：[ARCHITECTURE.md](ARCHITECTURE.md)、[DATABASE.md](DATABASE.md)

> **現況說明**：目前（M0 + M1.1）僅實作健康檢查端點與 Django admin。完整 REST API（profile、health records、trend）規劃於 **M1.4**，JWT 認證規劃於 **M1.3**。本文件明確標示各端點狀態，避免將規劃當現況。

---

## 1. 現有 HTTP 端點

| 方法 | 路徑 | 用途 | 認證 | 狀態 |
| --- | --- | --- | --- | --- |
| GET | \`/healthz/\` | Liveness probe | 無 | ✅ |
| GET | \`/readyz/\` | Readiness probe（DB + cache） | 無 | ✅ |
| — | \`/admin/\` | Django 管理後台 | Session | ✅ |

### GET /healthz/（Liveness）

程序活著就回 200，**不檢查任何外部相依**。供 k8s liveness probe 使用。

\`\`\`json
{ "status": "ok" }
\`\`\`

### GET /readyz/（Readiness）

檢查 DB 與 cache 是否可用。供 k8s readiness probe 使用。

\`\`\`json
{ "status": "ok", "checks": { "database": "ok", "cache": "ok" } }
\`\`\`

異常時回 \`503\`、\`status: "degraded"\`。**為何區分 liveness / readiness**：liveness 失敗 → 重啟容器；readiness 失敗 → 暫時移出流量但不重啟。詳見 [architecture.md](architecture.md)、[deployment.md](deployment.md)。

---

## 2. 應用核心（Domain）— 已實作

BMI 計算為純函式，無框架相依（[architecture.md](architecture.md#3-簽名級設計決策age-在-modelbmi-不在-model)）：

- \`compute_bmi(weight_kg, height_cm) -> Decimal\`
- \`classify_bmi(bmi) -> BMICategory\`（台灣國健署切點：< 18.5 過輕、< 24 正常、< 27 過重、≥ 27 肥胖）

---

## 3. Application 層（讀寫分離）— 已實作

M1.2 已實作 application 層，目前由測試與（未來）DRF view 呼叫，尚未直接 HTTP 暴露。這是輕量 CQRS：讀走 selector、寫走 service。

### 讀（selectors.py / Query）

| 函式 | 簽章 | 說明 |
| --- | --- | --- |
| \`latest_bmi\` | \`(user) -> BMIResult \| None\` | 跨實體組裝：Profile 身高 + 最新 HealthRecord 體重 → 計算 + 分類。身高或紀錄缺一回 \`None\` |
| \`weight_trend\` | \`(user, *, limit=90) -> list[WeightPoint]\` | 體重趨勢（時間升冪），以 \`.values()\` 只取需要欄位 |

**回傳契約（value object，凍結 dataclass）**：

\`\`\`python
@dataclass(frozen=True, slots=True)
class BMIResult:
    value: Decimal          # 例：Decimal("24.2")
    category: BMICategory   # 例：BMICategory.OVERWEIGHT
    weight_kg: Decimal
    height_cm: Decimal

@dataclass(frozen=True, slots=True)
class WeightPoint:
    recorded_at: str        # ISO 8601
    weight_kg: Decimal
\`\`\`

### 寫（services.py / Command）

| 函式 | 簽章 | 說明 |
| --- | --- | --- |
| \`record_measurement\` | \`(user, MeasurementInput) -> HealthRecord\` | 業務驗證（在交易外）+ 窄 \`transaction.atomic()\` 寫入 |

**輸入契約 / 例外**：

\`\`\`python
@dataclass(frozen=True, slots=True)
class MeasurementInput:
    weight_kg: Decimal
    body_fat_pct: Decimal | None = None
    waist_cm: Decimal | None = None
    recorded_at: datetime | None = None    # 省略則用 timezone.now()

class HealthValidationError(Exception):
    """領域驗證錯誤；由 interface 層（M1.4）轉成 400。service 不知道 HTTP。"""
\`\`\`

> 設計理由（窄交易、value object、領域例外不知道 HTTP）見 [architecture.md](architecture.md#4-application-層輕量-cqrs讀寫分離-m12)。

---

## 4. 規劃中的 REST API（M1.3 / M1.4）

以下為規劃設計，**尚未實作**。實作時以 DRF 提供並產出 OpenAPI。

### 認證（M1.3）

| 方法 | 路徑（規劃） | 用途 |
| --- | --- | --- |
| POST | \`/api/auth/register/\` | 註冊（顯式建立 User + Profile，同一交易，不用 signal） |
| POST | \`/api/auth/token/\` | 登入，取得 access + refresh |
| POST | \`/api/auth/token/refresh/\` | 以 refresh 換新 access |

### Profile / Health（M1.4，對應已實作的 service / selector）

| 方法 | 路徑（規劃） | 背後 | 用途 |
| --- | --- | --- | --- |
| GET | \`/api/profile/\` | model property | 取得 profile（含計算出的 age） |
| PATCH | \`/api/profile/\` | service | 更新 profile |
| POST | \`/api/health/records/\` | \`record_measurement\` | 新增量測 |
| GET | \`/api/health/records/\` | selector | 列出量測（分頁、時間排序） |
| GET | \`/api/health/bmi/\` | \`latest_bmi\` | 最新 BMI |
| GET | \`/api/health/trend/\` | \`weight_trend\` | 體重趨勢 |

### 規劃回應契約範例（BMI，對應 BMIResult）

\`\`\`jsonc
// GET /api/health/bmi/  →  200
{
  "bmi": 24.2,
  "category": "overweight",
  "based_on": { "weight_kg": 70.0, "height_cm": 170.0, "recorded_at": "2026-05-31T08:00:00+08:00" }
}
\`\`\`

---

## 5. API 設計原則（M1.4 實作時遵循）

- **View 薄**：CBV / generics，只負責 HTTP I/O，呼叫 service / selector，不放 business logic。
- **Serializer 純 I/O**：只做欄位驗證與序列化。
- **寫走 service、讀走 selector**：對應 §3 已實作的 application 層。
- **領域例外 → HTTP 轉譯在 view**：\`HealthValidationError\` → 400、重複資源 → 409（見 [architecture.md](architecture.md#4-application-層輕量-cqrs讀寫分離-m12)）。
- **型別化 request/response**、**統一 error 格式**（code / message / detail）。

---

## 6. OpenAPI / 文件化（規劃）

M1.4 起評估導入 \`drf-spectacular\` 自動產生 OpenAPI 3 與 Swagger UI（\`/api/schema/\`、\`/api/docs/\`）。
