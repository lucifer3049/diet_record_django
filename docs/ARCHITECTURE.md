# 系統架構（Architecture）

> 回到 [README](../README.md) ｜ 相關：[DATABASE.md](DATABASE.md)、[API.md](API.md)、[DEVELOPER-GUIDE.md](DEVELOPER-GUIDE.md)

---

## 1. 架構風格：Modular Monolith

本專案採**模組化單體**，而非微服務。

**理由（trade-off）**：在單人開發、domain 尚未穩定的階段，微服務帶來的分散式交易、服務間通訊、獨立部署等複雜度遠超過其效益——是典型的過度設計。模組化單體讓我們在單一程式內維持清楚的模組邊界（每個 \`apps/<app>\` 是一個有界的功能單元），未來若某模組真的需要獨立擴展，可沿既有邊界拆分，成本可控。

---

## 2. 分層架構（務實的 Clean Architecture）

採務實的分層，**非完整 Hexagonal / ports-adapters**。

**為何不一開始上滿 Hexagonal**：架構模式是用來解決你親身遇到的痛。目前沒有任何「需要抽換的外部 adapter」，硬做 port/adapter 是儀式而非價值（YAGNI）。真正引入 port 的時機是 **M4**——LLM 要能在 OpenAI / Gemini 間抽換，屆時 \`AIProvider\` port 才有實質意義。

### 四層職責

| 層 | 放在哪 | 職責 | 規則 |
| --- | --- | --- | --- |
| **Interface（介面）** | DRF View + Serializer | HTTP 請求/回應、序列化 | 薄；不放 business logic |
| **Application（應用）** | \`services.py\`（寫）、\`selectors.py\`（讀） | 用例編排、交易邊界、跨實體組裝 | 呼叫 domain + infrastructure |
| **Domain（領域）** | \`domain.py\`（純函式）、model 內在不變式 | 業務規則與公式 | 零框架相依，可即時單元測試 |
| **Infrastructure（基礎設施）** | Django ORM / Model / DB / Cache | 持久化、外部資源 | 框架的事 |

### 目錄 → 層 對照（health app，M1.2 後現況）

\`\`\`
apps/health/
├── domain.py        ← Domain：compute_bmi / classify_bmi（純函式、無 DB）        ✅ M1.1
├── models.py        ← Infrastructure：HealthRecord、QuerySet（ORM）             ✅ M1.1
├── selectors.py     ← Application（讀）：latest_bmi / weight_trend              ✅ M1.2
├── services.py      ← Application（寫）：record_measurement                     ✅ M1.2
├── serializers.py   ← Interface                                                ⬜ M1.4
├── views.py         ← Interface                                                ⬜ M1.4
└── admin.py         ← Infrastructure / glue                                    ✅ M1.1
\`\`\`

---

## 3. 簽名級設計決策：age 在 model，BMI 不在 model

這組對比是本專案分層思維的核心，務必理解。**M1.2 已將 BMI 的組裝在 selector 落地**，下方為實際程式碼。

### age → 放 model 的 @property（正當）

\`\`\`python
# apps/accounts/models.py
@property
def age(self) -> int | None:
    if self.birth_date is None:
        return None
    today = date.today()
    before_birthday = (today.month, today.day) < (self.birth_date.month, self.birth_date.day)
    return today.year - self.birth_date.year - int(before_birthday)
\`\`\`

\`age\` 由 \`birth_date\` + 今天算出——**單一實體、純計算、無副作用、不需查詢其他表**。放 model property 完全正當。

### BMI → 放 application 層的 selector（M1.2 已實作）

BMI 需要 \`height_cm\`（在 \`UserProfile\`）**和** \`weight_kg\`（在 \`HealthRecord\`）——**跨兩個實體**。

若硬掛在 \`HealthRecord.bmi\`，model 就得 \`self.user.profile.height_cm\` 反向抓另一張表 → 隱性耦合 + N+1 風險。正確切法：

- **公式**是純領域邏輯 → \`domain.py\` 的 \`compute_bmi(weight, height)\`（純函式）。
- **取數據**（抓 profile 身高 + 最新體重）是 application 的職責 → \`selectors.py\` 的 \`latest_bmi(user)\`。

\`\`\`python
# apps/health/selectors.py（M1.2 實際程式碼）
@dataclass(frozen=True, slots=True)
class BMIResult:
    """跨實體計算結果的 value object：對外契約，與 ORM 解耦。"""
    value: Decimal
    category: BMICategory
    weight_kg: Decimal
    height_cm: Decimal


def latest_bmi(user: User) -> BMIResult | None:
    height_cm: Decimal | None = getattr(user.profile, "height_cm", None)
    if height_cm is None:
        return None
    record = HealthRecord.objects.for_user(user).most_recent_first().first()
    if record is None:
        return None
    bmi = compute_bmi(record.weight_kg, height_cm)          # Domain 純函式
    return BMIResult(value=bmi, category=classify_bmi(bmi),
                     weight_kg=record.weight_kg, height_cm=height_cm)
\`\`\`

**判斷準則**：純計算、單一實體 → model property；需要查詢、跨實體組裝 → selector。

---

## 4. Application 層：輕量 CQRS（讀寫分離）— M1.2

M1.2 將 application 層拆成讀、寫兩個檔，是**程式碼層級的 CQRS**（非分離讀寫資料庫）。

| 檔 | 職責 | CQRS | 關鍵紀律 |
| --- | --- | --- | --- |
| \`selectors.py\` | 讀：查詢 + 跨實體組裝 | Query | 防 N+1、回明確型別、不寫 DB |
| \`services.py\` | 寫：用例編排 + 交易 | Command | 窄交易邊界、業務驗證、可回滾 |

**為何讀寫分檔**：讀的關注點（查詢效能、N+1、組裝）與寫的關注點（驗證、交易、一致性）本質不同，分檔讓每個檔心智單純、測試聚焦。這是 CQRS 最務實、不過度的落地——不需要分離資料庫，只在程式碼層級分職責。

### 窄交易邊界（service）

\`\`\`python
# apps/health/services.py（M1.2 實際程式碼，節錄）
def record_measurement(user: User, data: MeasurementInput) -> HealthRecord:
    # 驗證等純邏輯放在 atomic 之外，避免延長持鎖時間
    if data.weight_kg <= 0:
        raise HealthValidationError("weight_kg must be positive")
    ...
    recorded_at = data.recorded_at or timezone.now()
    with transaction.atomic():                 # 只包住「真正寫 DB」
        return HealthRecord.objects.create(user=user, weight_kg=data.weight_kg, ...)
\`\`\`

**為何窄**：未來 service 會呼叫 LLM（數秒 I/O）。若把驗證、外部呼叫都包進交易，會長時間握著 DB 連線與鎖，高併發時連線池枯竭。交易範圍要窄、明確，只圈住寫入。

### 對外契約用 value object，不回 dict / 不回 model

application 層對外回傳**凍結 dataclass**（\`BMIResult\` / \`WeightPoint\` / \`MeasurementInput\`），而非：

- 不回 \`dict\`：無型別、key 打錯 runtime 才爆。
- 不直接回 \`HealthRecord\` model：會讓上層（view/serializer）碰到 ORM 物件、誘發 lazy query（N+1 溫床）。

凍結 dataclass 提供明確型別（mypy 可驗）、不可變、與 ORM 解耦——是 application 層乾淨的對外邊界。

### 領域例外不知道 HTTP

\`record_measurement\` 驗證失敗時拋 \`HealthValidationError\`（領域例外），**不**回傳 HTTP 狀態碼。把領域錯誤轉成 400/409 是 **interface 層（M1.4 的 view）** 的職責。這條界線確保 application 層不耦合 web 框架，可在非 HTTP 情境（如 Celery task）重用。

---

## 5. 資料建模：穩定屬性 vs 時序資料

| 類型 | 範例 | 放哪 | 原因 |
| --- | --- | --- | --- |
| 穩定屬性 | gender、birth_date、height | \`UserProfile\`（OneToOne） | 相對不變 |
| 時序資料 | weight、body_fat、waist | \`HealthRecord\`（time-series） | 隨時間變動、要畫趨勢 |

把體重塞進 profile，之後就做不出趨勢圖。Profile 與 User 分離也是刻意——auth 關注「登入身分」，profile 關注「領域屬性」，避免養出 fat model。詳見 [database.md](database.md)。

---

## 6. 其他關鍵決策

### 不使用 Signal

Profile 的建立**不**透過 \`post_save\` signal，而是在 application 層（M1.3 的註冊 service）**顯式建立**。

**理由**：signal 是 magic behavior——難以追蹤、難以測試、難以納入交易控制。顯式建立讓「建立 profile」這件事看得見、可在 \`transaction.atomic()\` 內與 User 一起建立、可單元測試。

### 明確交易邊界（ATOMIC_REQUESTS = False）

不使用 \`ATOMIC_REQUESTS = True\`（不把整個 request 包進交易），改用明確的 \`transaction.atomic()\` 只包住寫 DB 那幾行。理由見 §4 的窄交易說明。

### 自訂 User（第一天就鎖定）

\`AUTH_USER_MODEL = "accounts.User"\` 在第一次 migrate 前就設定。Django 中途更換 User model 是出名的痛（需砍 migration/DB）。

---

## 7. 未來架構演進

| 里程碑 | 引入 | 屬於哪層 |
| --- | --- | --- |
| M3 | Celery task（ETL）、PostgreSQL 全文檢索 | Infrastructure / Application |
| M4 | \`AIProvider\` port + OpenAI/Gemini adapter、DI | Domain（介面）/ Infrastructure（實作） |
| M5 | RAG pipeline、pgvector、embedding/chunk/retrieval 策略 | Application / Infrastructure |
| M6 | structured logging、tracing、metrics | 橫切（observability） |

**M4 是分層的試金石**：屆時會把 LLM 呼叫抽象成 port（domain 定義介面），具體 provider 作為 adapter（infrastructure 實作），透過 DI 注入。這是本專案唯一真正需要 ports-adapters 的地方。

> 向量資料庫選型：在本規模、單機部署下選 **pgvector**（勝過 Qdrant/Milvus），可省一整套額外基礎設施。
