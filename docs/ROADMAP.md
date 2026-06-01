# AI Nutrition Advisor — 開發路線圖（Roadmap）

> 回到 [README](../README.md) ｜ 相關：[ARCHITECTURE.md](ARCHITECTURE.md)、[DEVELOPER-GUIDE.md](DEVELOPER-GUIDE.md)
>
> 學習導向、可演進專案。每個里程碑 = 一條能跑、能 demo 的 vertical slice。
> 原則：先做出能跑的東西 → 親身體驗每個 pattern 為何存在 → 邊界乾淨。拒絕 over-engineering。

## 進度總覽

- [x] **M0** Walking Skeleton ✅
- [~] **M1** 使用者 + 健康指標（M1.1、M1.2 完成）
- [ ] **M2** 飲食紀錄（純 CRUD）
- [ ] **M3** 食物知識庫 + ETL（單一來源、無向量）
- [ ] **M4** LLM 營養分析（無 RAG）→ 此時才引入 \`AIProvider\` port
- [ ] **M5** RAG + pgvector
- [ ] **M6** 擴充 + observability + 上雲

**架構決策（M1–M3）**：務實 Django service layer，非完整 Hexagonal。
**層對應**：domain = \`domain.py\` + model 不變式｜application = \`services.py\`(寫) + \`selectors.py\`(讀)｜infrastructure = ORM/DB/cache｜interface = DRF view + serializer。

---

## M0 — Walking Skeleton ✅

- [x] 專案結構（modular monolith 雛形）
- [x] 相依管理（uv + pyproject）
- [x] 設定分層 base/dev/prod（環境變數驅動，secret 不寫死）
- [x] 自訂 User model（鎖定 \`AUTH_USER_MODEL\`）
- [x] Docker 多階段 + compose（web/db/redis，含 healthcheck 啟動順序）
- [x] 健康檢查 \`/healthz\`（liveness）+ \`/readyz\`（readiness：DB + Redis）
- [x] smoke test（liveness 零依賴 + readiness 整合）
- [x] GitHub Actions CI：ruff + ruff format + mypy + \`makemigrations --check\` + pytest
- [x] 首次 commit + push，CI 設定就緒

**踩過的坑**（已收斂進 \`bootstrap.sh\` 與 [developer-guide.md](developer-guide.md#9-常見問題與排錯指南)）：MSYS 路徑轉換、settings 沒拆套件、apps.py name、urls.py 沒覆蓋、Dockerfile 行內註解、manage.py 缺型別、mypy exclude 對命令列無效。

---

## M1 — 使用者 + 健康指標（進行中）

### M1.1 領域模型 + 純領域邏輯 ✅
- [x] accounts：\`UserProfile\`（gender/birth_date/height/activity/goal）+ \`User.__str__\`
- [x] accounts：\`age\` 為 model property（單一實體、純計算）
- [x] health：\`HealthRecord\`（weight/body_fat/waist/recorded_at，time-series，含中文 verbose_name）
- [x] health：custom QuerySet（\`for_user\` / \`chronological\` / \`most_recent_first\`）
- [x] health：複合索引 \`(user, -recorded_at)\`
- [x] health/\`domain.py\`：\`compute_bmi\` + \`classify_bmi\`（純函式，台灣國健署切點）
- [x] 純領域單元測試（無 DB）+ 整合測試（4 passed）

**設計重點**：\`age\` 放 model、BMI 不放 model（跨實體）→ 公式進 domain、取數進 selector。詳見 [architecture.md](architecture.md#3-簽名級設計決策age-在-modelbmi-不在-model)。

### M1.2 application 層 ✅
- [x] \`selectors.py\`（讀／Query）：\`latest_bmi\`（跨 Profile 身高 + 最新 HealthRecord 體重 → \`compute_bmi\` → \`classify_bmi\`）、\`weight_trend\`（\`.values()\` 只取需要欄位）
- [x] \`services.py\`（寫／Command）：\`record_measurement\`（業務驗證在 atomic 外、窄 \`transaction.atomic()\` 只包寫入）
- [x] 對外契約用凍結 dataclass value object（\`BMIResult\` / \`WeightPoint\` / \`MeasurementInput\`），與 ORM 解耦
- [x] 領域例外 \`HealthValidationError\`（service 不知道 HTTP，由 interface 層轉譯）
- [x] application 層整合測試（5 個，含跨實體組裝、None 邊界、驗證、趨勢排序）→ 累計 9 passed

**設計重點**：輕量 CQRS（程式碼層級讀寫分離，非分離資料庫）；BMI 的跨實體組裝在 selector 落地，證明「為何不放 model」。詳見 [architecture.md](architecture.md#3-簽名級設計決策age-在-modelbmi-不在-model) 與 [api.md](api.md#3-application-層讀寫分離已實作)。

### M1.3 JWT 認證（accounts）— 下一步
- [ ] SimpleJWT：access/refresh、登入、刷新
- [ ] 註冊 service：顯式建立 User + UserProfile（同一交易、不用 signal）

### M1.4 interface 層（DRF）
- [ ] 薄 view（CBV/generics）+ 純 I/O serializer
- [ ] endpoints：profile、health records（建立/列表）、bmi、trend
- [ ] 評估導入 drf-spectacular（OpenAPI）

### M1.5 測試
- [ ] factory_boy factories（User/Profile/HealthRecord）
- [ ] service / selector / API 測試補強；導入 pytest-cov（目標 ≥ 80%）

### M1.6 Vue3 thin slice（並行）
- [ ] 登入 + 健康紀錄頁（typed API client）

---

## M2 — 飲食紀錄（純 CRUD）
- [ ] \`diary\`：早午晚點心、食物搜尋、DRF API｜N+1 / index / 送出 idempotency

## M3 — 食物知識庫 + ETL
- [ ] \`foods\`：資料模型 + PostgreSQL 全文檢索（先不上向量）
- [ ] 一條 ETL（單一來源）+ 增量更新 + Celery task + 重試

## M4 — LLM 營養分析（無 RAG）
- [ ] \`ai\`：\`AIProvider\` port + OpenAI/Gemini adapter、DI、prompt 管理、async + timeout/retry
- [ ] 親眼看到幻覺與來源不可信 → M5 的動機

## M5 — RAG + pgvector
- [ ] \`knowledge_base\`：embedding / chunk / retrieval / context 組裝 / 引用來源

## M6 — 擴充 + observability + 上雲
- [ ] 運動 / 食譜推薦（重用 AI 層）、Celery Beat 排程化
- [ ] structured logging + tracing + metrics、prod image 移除 dev 依賴、上雲（見 [deployment.md](deployment.md)）