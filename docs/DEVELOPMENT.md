# 開發流程（Development）

> 回到 [README](../README.md) ｜ 相關：[code_quality.md](code_quality.md)、[testing.md](testing.md)、[developer-guide.md](developer-guide.md)、[commands.md](commands.md)

---

## 1. 每日開發循環

```
┌─ git switch main && git pull        # 同步最新
│
├─ git switch -c feature/<簡述>        # 開 feature branch
│
├─ 開發（依分層架構放置程式碼）
│     ├─ domain.py     純規則 / 公式
│     ├─ services.py   寫入用例（含交易）
│     ├─ selectors.py  讀取 / 組裝
│     ├─ models.py     資料結構
│     └─ views/serializers  HTTP I/O
│
├─ 四道品質閘門（本機）
│     ├─ ruff check --fix .
│     ├─ ruff format .
│     ├─ mypy .
│     └─ pytest -q
│
├─ git commit + push
│
└─ 開 PR → CI 綠燈 → review → merge
```

---

## 2. 程式碼放在哪一層？

新增功能時，先問「這段邏輯屬於哪一層」：

| 這段程式碼是… | 放哪 | 範例 |
| --- | --- | --- |
| 純計算、單一實體、無 DB | model `@property` 或 `domain.py` | `age`、`compute_bmi` |
| 跨實體組裝、需要查詢 | `selectors.py` | `latest_bmi`（Profile 身高 + Record 體重） |
| 寫入、需要交易控制 | `services.py` | `record_measurement` |
| HTTP 請求/回應 | `views.py` + `serializers.py` | API endpoint |
| 資料結構、ORM 查詢片段 | `models.py`（含 custom QuerySet） | `HealthRecord.objects.for_user()` |

詳細判準見 [architecture.md](architecture.md)。

---

## 3. 新增一個 Django App

```bash
# 1. 建立目錄與檔案（沿用 bootstrap 思路，直接寫檔避免 reshaping 遺漏）
mkdir -p apps/<name>/migrations
: > apps/<name>/__init__.py
: > apps/<name>/migrations/__init__.py

# 2. apps.py（注意 name 指向 apps.<name>）
cat > apps/<name>/apps.py << 'EOF'
from django.apps import AppConfig


class <Name>Config(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.<name>"
    label = "<name>"
EOF

# 3. 註冊到 config/settings/base.py 的 LOCAL_APPS
#    LOCAL_APPS = ["apps.accounts", "apps.health", "apps.<name>"]
```

> **關鍵**：`name="apps.<name>"`（import 路徑）+ `label="<name>"`（Django 內部識別字）兩者都要設。漏設 `name` 會出現 `Cannot import '<name>'` 錯誤——這是手動建立 app 的常見陷阱。

---

## 4. 新增 / 修改 Model

```bash
# 1. 修改 models.py

# 2. 產生 migration
docker compose run --rm web python manage.py makemigrations

# 3. 檢視產生的 migration（重要：確認沒有意外操作）
#    apps/<name>/migrations/000X_*.py

# 4. 套用
docker compose exec web python manage.py migrate
```

修改既有資料表時，注意 migration 安全（null/default、分次部署），見 [database.md](database.md#migration-安全演進原則後續里程碑)。

---

## 5. Branch 策略

採輕量的 trunk-based 風格：

| Branch | 用途 | 命名 |
| --- | --- | --- |
| `main` | 永遠可部署、CI 須綠 | — |
| `feature/*` | 功能開發 | `feature/<里程碑或簡述>`，如 `feature/2026_05_31_專案開發第一步` |
| `fix/*` | 修錯 | `fix/<簡述>` |

- 從 `main` 切出，完成後以 PR 合回 `main`。
- 保持 branch 短命、PR 小顆，降低衝突與 review 負擔。

---

## 6. Commit 流程

```bash
git add .
git commit -m "M1.x: <動詞開頭的簡述>"
git push -u origin <branch>
```

**Commit message 慣例**（建議）：

- 以里程碑前綴標示脈絡：`M1.2: add health selectors for BMI`
- 動詞開頭、描述「做了什麼」而非「改了哪個檔」。
- 一個 commit 聚焦一件事，便於日後 review 與 revert。

---

## 7. Pull Request / Code Review 流程

1. push feature branch → 在 GitHub 開 PR（base: `main`）。
2. **CI 必須綠燈**（ruff / format / mypy / migration check / pytest）才可合併。
3. Review 關注點（見 [developer-guide.md](developer-guide.md#code-review-流程)）：
   - 分層是否正確（business logic 沒漏進 view/serializer）。
   - 是否有 N+1、缺索引、交易範圍過寬。
   - migration 是否安全、backward compatible。
   - 測試是否涵蓋（domain 純測 + 整合測）。
4. 通過後 merge（建議 squash），刪除 feature branch。

---

## 8. 處理 lint / 型別錯誤的心法

當閘門報錯，先分辨 **signal（真問題）** vs **noise（設定/誤報）**：

- **真 bug**：如函式縮排錯位、重複定義、import 失敗——修程式碼。
- **框架慣例誤報**：如 RUF012 對 Meta、admin 泛型——調整 `pyproject.toml` 規則（見 [code_quality.md](code_quality.md)）。
- **第三方無 stub**：如 `environ`——per-module override 精準消音。

測試紅燈時，先判斷「程式錯」還是「測試錯」——例如 BMI 測試曾因期望值未隨輸入更新而紅，手算驗證即知是測試斷言錯、程式對。

更多排錯見 [developer-guide.md](developer-guide.md#常見問題與排錯指南)。
