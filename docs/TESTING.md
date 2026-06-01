# 測試說明（Testing）

> 回到 [README](../README.md) ｜ 相關：[CODE_QUALITY.md](CODE_QUALITY.md)、[COMMANDS.md](COMMANDS.md)

---

## 1. 測試框架

| 工具 | 用途 |
| --- | --- |
| pytest | 測試執行器 |
| pytest-django | Django 整合（test DB、\`client\` fixture、\`@pytest.mark.django_db\`、\`db\` fixture） |
| factory_boy | 測試資料工廠（M1.5 起使用） |

設定於 \`pyproject.toml\`：

\`\`\`toml
[tool.pytest.ini_options]
DJANGO_SETTINGS_MODULE = "config.settings.dev"
python_files = ["test_*.py", "*_test.py", "tests.py"]
\`\`\`

> 注意 \`python_files\` 同時匹配 \`tests.py\` 與 \`test_*.py\`。M1.2 起 application 層測試獨立為 \`test_application.py\`，與 \`tests.py\`（純領域）分開。

---

## 2. 測試分類（重要觀念）

本專案刻意區分兩類測試，對應分層架構：

### 純領域測試（無 DB、毫秒級）

測試 \`domain.py\` 的純函式，不需資料庫，執行極快。檔案：\`apps/health/tests.py\`。

\`\`\`python
def test_compute_bmi_basic() -> None:
    # 170cm / 70kg → 24.2（純計算，無 DB）
    assert compute_bmi(Decimal("70"), Decimal("170")) == Decimal("24.2")
\`\`\`

### 整合測試（需 DB / cache）

需要資料庫或外部資源者，標記 \`@pytest.mark.django_db\`。涵蓋 application 層（service / selector）與 health check。檔案：\`core/tests.py\`、\`apps/health/test_application.py\`。

\`\`\`python
@pytest.mark.django_db
def test_latest_bmi_assembles_across_entities(user: User) -> None:
    record_measurement(user, MeasurementInput(weight_kg=Decimal("70")))
    result = latest_bmi(user)
    assert result is not None
    assert result.value == Decimal("24.2")
    assert result.category is BMICategory.OVERWEIGHT
\`\`\`

---

## 3. Application 層測試（M1.2）

\`apps/health/test_application.py\` 涵蓋 5 個案例，示範各層測試重點：

| 測試 | 驗證重點 | 對應設計 |
| --- | --- | --- |
| \`test_record_measurement_persists\` | service 正確寫入 | 寫入用例 |
| \`test_record_measurement_rejects_nonpositive_weight\` | 驗證失敗拋 \`HealthValidationError\` | 領域例外 |
| \`test_latest_bmi_assembles_across_entities\` | 跨 Profile + Record 組裝 BMI | 簽名級決策落地 |
| \`test_latest_bmi_none_without_height\` | 缺身高時回 None | 邊界條件 |
| \`test_weight_trend_is_chronological\` | 趨勢時間升冪 | selector 排序 |

### fixture 與型別（strict mypy 注意）

pytest-django 的 \`db\` fixture 在 strict 模式下也須型別標註，標為 \`None\`（它只啟用 DB 存取、不回傳有用值）：

\`\`\`python
@pytest.fixture
def user(db: None) -> User:        # ← db: None，否則 mypy no-untyped-def
    u = User.objects.create_user(username="alice", password="x")
    UserProfile.objects.create(user=u, height_cm=Decimal("170"))
    return u
\`\`\`

> 這是 M1.2 實際踩到的點：strict mypy 會要求連 fixture 參數都標型別。詳見 [developer-guide.md](developer-guide.md#94-lint-型別多為設定非真-bug)。

---

## 4. 執行測試

\`\`\`bash
# 全部測試（需要 db + redis，勿加 --no-deps）
docker compose run --rm web pytest -q

# 只跑純領域測試（無 DB，極快）
docker compose run --rm --no-deps web pytest apps/health/tests.py -q

# 只跑 application 層測試
docker compose run --rm web pytest apps/health/test_application.py -q

# 單一測試函式
docker compose run --rm web pytest apps/health/test_application.py::test_latest_bmi_assembles_across_entities -q

# 詳細 / 遇第一個失敗即停
docker compose run --rm web pytest -v
docker compose run --rm web pytest -x
\`\`\`

目前測試數：**9 passed**（2 純領域 + 2 health check 整合 + 5 application 整合）。

---

## 5. 測試資料工廠（M1.5 規劃）

M1.5 起以 factory_boy 取代手刻 fixture：

\`\`\`python
class UserFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = User
    username = factory.Sequence(lambda n: f"user{n}")

class UserProfileFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = UserProfile
    user = factory.SubFactory(UserFactory)
    height_cm = 170
\`\`\`

---

## 6. 測試策略（後續里程碑）

| 層 | 測試重點 | 是否需 DB |
| --- | --- | --- |
| Domain | 公式、邊界值、例外（如 \`compute_bmi\` 對 height ≤ 0 拋錯） | 否 |
| Application（service） | 用例正確性、交易回滾、驗證 | 是 |
| Application（selector） | 查詢正確、N+1 防護、跨實體組裝 | 是 |
| Interface（API） | 狀態碼、序列化、權限、認證 | 是 |

**Coverage 目標**：≥ 80%（規劃以 \`pytest-cov\` 量測並納入 CI 門檻）。

\`\`\`bash
docker compose run --rm web pytest --cov=apps --cov=core --cov-report=term-missing
\`\`\`

CI 如何執行測試見 [code_quality.md](code_quality.md) 與 [deployment.md](deployment.md)。
