# 程式碼品質（Ruff、MyPy、Lint）

> 回到 [README](../README.md) ｜ 相關：[testing.md](testing.md)、[development.md](development.md)、[commands.md](commands.md)

---

## 1. 工具總覽

| 工具 | 角色 | 取代 |
| --- | --- | --- |
| **Ruff** | Lint + Format | flake8 + isort + Black |
| **mypy (strict)** | 靜態型別檢查 | — |
| **django-stubs / DRF stubs** | Django / DRF 型別資訊 | — |

選 Ruff 的理由：`ruff format` 已涵蓋 Black 功能，`ruff check` 涵蓋 isort 與多數 flake8 外掛——少裝幾個工具、更好的 DX、更快。

---

## 2. 推送前四道閘門

```bash
docker compose run --rm --no-deps web ruff check --fix .   # 1. lint（自動修可修項）
docker compose run --rm --no-deps web ruff format .         # 2. 格式化
docker compose run --rm --no-deps web mypy .                # 3. 型別檢查
docker compose run --rm web pytest -q                       # 4. 測試（需 DB）
```

**為何先在本機跑**：CI 是最後一道防線，不是第一個 feedback loop。本機綠了再 push，省下 CI 來回等待（fail fast）。

> `ruff check --fix` 修語意類問題（import 排序、未使用 import 等）；`ruff format` 修排版（換行、空格）。兩者分工，需各跑一次才完全乾淨。

---

## 3. Ruff 設定（`pyproject.toml`）

```toml
[tool.ruff]
target-version = "py312"
line-length = 100
extend-exclude = ["**/migrations/**"]

[tool.ruff.lint]
select = ["E", "F", "I", "UP", "B", "DJ", "RUF"]
ignore = ["RUF001", "RUF002", "RUF003"]

[tool.ruff.lint.per-file-ignores]
"config/settings/*" = ["F403", "F405"]
"**/models.py" = ["RUF012"]
```

### 啟用的規則集

| 代碼 | 內容 |
| --- | --- |
| `E` | pycodestyle 錯誤 |
| `F` | pyflakes（未使用、未定義等） |
| `I` | isort（import 排序） |
| `UP` | pyupgrade（現代化語法） |
| `B` | flake8-bugbear（常見 bug 模式） |
| `DJ` | flake8-django（Django 慣例） |
| `RUF` | Ruff 專屬規則 |

### 停用 / 例外規則及其理由

這些不是偷懶，每一條都有明確權衡：

| 設定 | 範圍 | 理由 |
| --- | --- | --- |
| `ignore RUF001/002/003` | 全域 | 這組規則抓「視覺混淆字元」（如西里爾字母假冒拉丁字母）。但本專案以中文撰寫 docstring / 註解，全形標點 `，（）；` 正確且必要，在中文 codebase 誤報率極高。停用此組保護遠不及它製造的噪音 |
| `extend-exclude migrations` | migration 檔 | migration 是 Django 自動生成檔，超長 `help_text`、`dependencies=[...]` 等是框架標準寫法，不該手改、不該被 lint。用 `extend-exclude`（疊加）而非 `exclude`（覆蓋預設），保留 ruff 內建排除清單 |
| `models.py: RUF012` | model 檔 | RUF012 防「共享可變預設值」，但 `Meta.ordering`/`indexes` 是 Django 讀取的 class-level 設定，永不會被 per-instance mutate，規則不適用 |
| `settings/*: F403/F405` | settings | settings 慣用 `from .base import *`，star import 是刻意的 |

---

## 4. MyPy 設定（`pyproject.toml`）

```toml
[tool.mypy]
plugins = ["mypy_django_plugin.main"]
strict = true
exclude = ["migrations/"]

[[tool.mypy.overrides]]
module = "environ.*"
ignore_missing_imports = true

[[tool.mypy.overrides]]
module = "apps.*.admin"
disable_error_code = ["type-arg"]

[tool.django-stubs]
django_settings_module = "config.settings.dev"
```

### 設計原則：邏輯層維持 strict，glue 層精準放寬

| 設定 | 理由 |
| --- | --- |
| `strict = true` | 邏輯層（`apps/`、`core/`、未來 service）享有最嚴格的型別保護 |
| `exclude migrations` | 自動生成檔，不納入 strict |
| `environ.*: ignore_missing_imports` | `django-environ` 上游無型別 stub。**精準**對這個套件消音，而非整包排除 settings——這樣 settings 程式碼若寫出真正的型別錯誤仍抓得到（範圍最小、保護最大） |
| `apps.*.admin: disable type-arg` | `ModelAdmin` 在 strict 下是泛型，理論上要寫 `ModelAdmin[HealthRecord]`，但直接下標在 runtime 會爆（需 django-stubs-ext monkeypatch）。為 type admin 而加 runtime 依賴 + 重 build 屬過度設計；admin 是 glue，型別價值低，故僅對 admin 模組關此規則 |

> **重要陷阱**：mypy 的 `exclude` 只在「遞迴探索」時生效，**對命令列明確傳入的路徑（如 `mypy .`）無效**。因此我們不靠 `exclude` 排除 settings，而用 per-module override 精準處理 `environ`。

---

## 5. CI 中的品質檢查

`.github/workflows/ci.yml` 在每次 push / PR 執行（含 postgres + redis service container）：

```yaml
- name: Lint
  run: uv run ruff check --output-format=github .
- name: Format check
  run: uv run ruff format --check .
- name: Type check
  run: uv run mypy .
- name: Migration safety
  run: uv run python manage.py makemigrations --check --dry-run
- name: Tests
  run: uv run pytest -q
```

- `--output-format=github`：錯誤以行內標註出現在 PR diff 上，DX 佳。
- `ruff format --check`：把格式漂移擋在 PR，而非事後吵 diff。
- `makemigrations --check`：擋下「改了 model 卻沒產 migration」的 PR（見 [database.md](database.md#migration-safetyci-閘門)）。

完整 CI 說明見 [deployment.md](deployment.md)。
