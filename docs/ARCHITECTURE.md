# 系統架構（Architecture）

> 回到 [README](../README.md) ｜ 相關：[database.md](database.md)、[api.md](api.md)、[developer-guide.md](developer-guide.md)

---

## 1. 架構風格：Modular Monolith

本專案採**模組化單體**，而非微服務。

**理由（trade-off）**：在單人開發、domain 尚未穩定的階段，微服務帶來的分散式交易、服務間通訊、獨立部署等複雜度遠超過其效益——是典型的過度設計。模組化單體讓我們在單一程式內維持清楚的模組邊界（每個 `apps/<app>` 是一個有界的功能單元），未來若某模組真的需要獨立擴展，可沿既有邊界拆分，成本可控。

```
┌──────────────────────── Modular Monolith ────────────────────────┐
│                                                                   │
│   apps/accounts        apps/health        apps/diary (M2)         │
│   ┌──────────┐         ┌──────────┐       ┌──────────┐            │
│   │ 使用者    │         │ 健康指標  │       │ 飲食紀錄  │  ...       │
│   └──────────┘         └──────────┘       └──────────┘            │
│        清楚的 app 邊界，未來可沿邊界拆分                              │
│                                                                   │
│   core/  ── 跨領域共用（healthcheck 等）                            │
│   config/ ── 組態：把系統組起來，不放 business code                  │
└───────────────────────────────────────────────────────────────────┘
```

---

## 2. 分層架構（務實的 Clean Architecture）

採務實的分層，**非完整 Hexagonal / ports-adapters**。

**為何不一開始上滿 Hexagonal**：架構模式是用來解決你親身遇到的痛。目前沒有任何「需要抽換的外部 adapter」，硬做 port/adapter 是儀式而非價值（YAGNI）。真正引入 port 的時機是 **M4**——LLM 要能在 OpenAI / Gemini 間抽換，屆時 `AIProvider` port 才有實質意義。

### 四層職責

| 層 | 放在哪 | 職責 | 規則 |
| --- | --- | --- | --- |
| **Interface（介面）** | DRF View + Serializer | HTTP 請求/回應、序列化 | 薄；不放 business logic |
| **Application（應用）** | `services.py`（寫）、`selectors.py`（讀） | 用例編排、交易邊界、跨實體組裝 | 呼叫 domain + infrastructure |
| **Domain（領域）** | `domain.py`（純函式）、model 內在不變式 | 業務規則與公式 | 零框架相依，可即時單元測試 |
| **Infrastructure（基礎設施）** | Django ORM / Model / DB / Cache | 持久化、外部資源 | 框架的事 |

```
HTTP Request
    │
    ▼
┌─────────────────┐
│ Interface       │  DRF View 解析請求 → 呼叫 service/selector
│ (View+Serializer)│  Serializer 只做 I/O 驗證與序列化
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Application      │  services.py：record_measurement（驗證＋交易＋寫入）
│ (services/       │  selectors.py：latest_bmi（讀取＋組裝）
│  selectors)      │
└────┬────────┬───┘
     │        │
     ▼        ▼
┌─────────┐ ┌──────────────┐
│ Domain  │ │ Infrastructure│
│ (純函式) │ │ (ORM/DB/Cache)│
│ compute │ │ HealthRecord  │
│ _bmi    │ │ UserProfile   │
└─────────┘ └──────────────┘
```

### 目錄 → 層 對照

```
apps/health/
├── domain.py        ← Domain：compute_bmi / classify_bmi（純函式、無 DB）
├── models.py        ← Infrastructure：HealthRecord、QuerySet（ORM）
├── selectors.py     ← Application（讀）  [M1.2 規劃]
├── services.py      ← Application（寫）  [M1.2 規劃]
├── serializers.py   ← Interface          [M1.4 規劃]
├── views.py         ← Interface          [M1.4 規劃]
└── admin.py         ← Infrastructure / glue
```

---

## 3. 簽名級設計決策：`age` 在 model，`BMI` 不在 model

這組對比是本專案分層思維的核心，務必理解。

### `age` → 放 model 的 `@property`（正當）

```python
# apps/accounts/models.py
@property
def age(self) -> int | None:
    if self.birth_date is None:
        return None
    today = date.today()
    before_birthday = (today.month, today.day) < (self.birth_date.month, self.birth_date.day)
    return today.year - self.birth_date.year - int(before_birthday)
```

`age` 由 `birth_date` + 今天算出——**單一實體、純計算、無副作用、不需查詢其他表**。放 model property 完全正當。

### `BMI` → 放 application 層的 selector（M1.2）

BMI 需要 `height_cm`（在 `UserProfile`）**和** `weight_kg`（在 `HealthRecord`）——**跨兩個實體**。

若硬掛在 `HealthRecord.bmi`，model 就得 `self.user.profile.height_cm` 反向抓另一張表 → 隱性耦合 + N+1 風險。正確切法：

- **公式**是純領域邏輯 → `domain.py` 的 `compute_bmi(weight, height)`（純函式）。
- **取數據**（抓 profile 身高 + 最新體重）是 application 的職責 → `selectors.py` 的 `latest_bmi(user)`。

```python
# apps/health/selectors.py（M1.2 規劃示意）
def latest_bmi(user: User) -> BMIResult | None:
    height = user.profile.height_cm                       # Infrastructure 取數
    record = HealthRecord.objects.for_user(user).most_recent_first().first()
    if height is None or record is None:
        return None
    bmi = compute_bmi(record.weight_kg, height)           # Domain 純函式
    return BMIResult(value=bmi, category=classify_bmi(bmi))
```

**判斷準則**：純計算、單一實體 → model property；需要查詢、跨實體組裝 → selector。

---

## 4. 資料建模：穩定屬性 vs 時序資料

另一個容易做錯的切分。

| 類型 | 範例 | 放哪 | 原因 |
| --- | --- | --- | --- |
| 穩定屬性 | gender、birth_date、height | `UserProfile`（OneToOne） | 相對不變 |
| 時序資料 | weight、body_fat、waist | `HealthRecord`（time-series） | 隨時間變動、要畫趨勢 |

把體重塞進 profile，之後就做不出趨勢圖。Profile 與 User 分離也是刻意——auth 關注「登入身分」，profile 關注「領域屬性」，避免養出 fat model。

詳見 [database.md](database.md)。

---

## 5. 其他關鍵決策

### 不使用 Signal

Profile 的建立**不**透過 `post_save` signal，而是在 application 層（M1.3 的註冊 service）**顯式建立**。

**理由**：signal 是 magic behavior——難以追蹤、難以測試、難以納入交易控制。顯式建立讓「建立 profile」這件事看得見、可在 `transaction.atomic()` 內與 User 一起建立、可單元測試。

### 明確交易邊界（`ATOMIC_REQUESTS = False`）

不使用 `ATOMIC_REQUESTS = True`（不把整個 request 包進交易）。改用明確的 `transaction.atomic()` 只包住「真正寫 DB」的那幾行。

**理由**：未來 service 會呼叫 LLM（數秒 I/O）。若整個 request 在交易裡，這段 I/O 會一直握著 DB 連線與鎖，高併發時連線池瞬間枯竭。交易範圍要**窄、明確**。

### 自訂 User（第一天就鎖定）

`AUTH_USER_MODEL = "accounts.User"` 在第一次 migrate 前就設定。Django 中途更換 User model 是出名的痛（需砍 migration/DB）。即使 M0 階段 User 還是空殼，也先建立以鎖定。

---

## 6. 未來架構演進

| 里程碑 | 引入 | 屬於哪層 |
| --- | --- | --- |
| M3 | Celery task（ETL）、PostgreSQL 全文檢索 | Infrastructure / Application |
| M4 | `AIProvider` port + OpenAI/Gemini adapter、DI | Domain（介面）/ Infrastructure（實作） |
| M5 | RAG pipeline、pgvector、embedding/chunk/retrieval 策略 | Application / Infrastructure |
| M6 | structured logging、tracing、metrics | 橫切（observability） |

**M4 是分層的試金石**：屆時會把 LLM 呼叫抽象成 port（domain 定義介面），具體 provider 作為 adapter（infrastructure 實作），透過 DI 注入。這是本專案唯一真正需要 ports-adapters 的地方。

> 向量資料庫選型：在本規模、單機部署下選 **pgvector**（勝過 Qdrant/Milvus），可省一整套額外基礎設施。
