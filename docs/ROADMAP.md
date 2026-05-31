# AI Nutrition Advisor — 開發路線圖

> 學習導向、可演進專案。每個里程碑 = 一條能跑、能 demo 的 vertical slice。
> 原則：先做出能跑的東西 → 親身體驗每個 pattern 為何存在 → 邊界乾淨。拒絕 over-engineering。

## 進度總覽
- [ ] M0 Walking Skeleton（進行中）
- [ ] M1 使用者 + 健康指標
- [ ] M2 飲食紀錄（純 CRUD）
- [ ] M3 食物知識庫 + ETL（單一來源、無向量）
- [ ] M4 LLM 營養分析（無 RAG）
- [ ] M5 RAG + pgvector
- [ ] M6 擴充 + observability + 上雲

---

## M0 — Walking Skeleton
目的：環境一致性、12-factor 設定、容器化、健康檢查、CI 綠燈。
- [x] 專案結構（modular monolith 雛形）
- [x] 相依管理（uv + pyproject）
- [x] 設定分層 base/dev/prod（環境變數驅動，secret 不寫死）
- [x] 自訂 User model 雛形（鎖定 AUTH_USER_MODEL，避免日後 migration 地獄）
- [x] Docker 多階段 + compose（web / db / redis）
- [x] 健康檢查 /healthz（liveness）+ /readyz（readiness：DB + Redis）
- [ ] （你執行）compose up + migrate，確認 /readyz 回 200
- [ ] （下一步）GitHub Actions CI：ruff + mypy + pytest 跑綠
- [ ] （下一步）首次 commit + 第一個 smoke test
刻意不做：DDD/Hexagonal 全套、repository/service 目錄、LLM、向量資料庫。

## M1 — 使用者 + 健康指標
- [ ] accounts：JWT + Refresh Token + Profile 欄位
- [ ] health：體重 / BMI / 體脂 紀錄 + 趨勢查詢
- [ ] 導入 service layer，畫出 fat model 的界線
- [ ] typed Django：custom manager/queryset、明確 transaction.atomic()
- [ ] Vue3 thin slice（登入 + 健康頁）並行起跑

## M2 — 飲食紀錄（純 CRUD）
- [ ] diary：早午晚點心、食物搜尋、DRF API
- [ ] N+1 / index 策略、送出 idempotency

## M3 — 食物知識庫 + ETL
- [ ] foods：資料模型 + PostgreSQL 全文檢索（先不上向量）
- [ ] 一條 ETL pipeline（單一來源）+ 增量更新 + Celery task + 重試

## M4 — LLM 營養分析（無 RAG）
- [ ] ai：抽象 AIProvider + OpenAI/Gemini 實作、DI、prompt 管理、async + timeout/retry
- [ ] 親眼看到幻覺與來源不可信 → 這就是 M5 的動機

## M5 — RAG + pgvector
- [ ] knowledge_base：embedding / chunk / retrieval / context 組裝 / 引用來源

## M6 — 擴充 + observability + 上雲
- [ ] 運動 / 食譜推薦（重用 AI 層）、Celery Beat 排程化
- [ ] structured logging + tracing + metrics、prod-lean image、上雲