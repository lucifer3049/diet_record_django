# 測試說明（Testing）

> 回到 [README](../README.md) ｜ 相關：[code_quality.md](code_quality.md)、[commands.md](commands.md)

---

## 1. 測試框架

| 工具 | 用途 |
| --- | --- |
| pytest | 測試執行器 |
| pytest-django | Django 整合（test DB、`client` fixture、`@pytest.mark.django_db`） |
| factory_boy | 測試資料工廠（M1.5 起使用） |

設定於 `pyproject.toml`：

```toml
[tool.pytest.ini_options]
DJANGO_SETTINGS_MODULE = "config.settings.dev"
python_files = ["test_*.py", "*_test.py", "tests.py"]
```

---

## 2. 測試分類（重要觀念）

本專案刻意區分兩類測試，對應分層架構：

### 純領域測試（無 DB、毫秒級）

測試 `domain.py` 的純函式，**不需資料庫**，執行極快。這是「domain layer 可即時單元測試」的具體體現。

```python
# apps/health/tests.py
from decimal import Decimal
from apps.health.domain import BMICategory, classify_bmi, compute_bmi


def test_compute_bmi_basic() -> None:
    # 170cm / 70kg → 24.2（純計算，無 DB）
    assert compute_bmi(Decimal("70"), Decimal("170")) == Decimal("24.2")


def test_classify_bmi_taiwan_cutoffs() -> None:
    assert classify_bmi(Decimal("18.4")) is BMICategory.UNDERWEIGHT
    assert classify_bmi(Decimal("23.9")) is BMICategory.NORMAL
    assert classify_bmi(Decimal("26.9")) is BMICategory.OVERWEIGHT
    assert classify_bmi(Decimal("27.0")) is BMICategory.OBESE
```

### 整合測試（需 DB / cache）

需要資料庫或外部資源者，標記 `@pytest.mark.django_db`。pytest-django 會自動建立 / 回收 test DB。

```python
# core/tests.py
import pytest
from django.test import Client


def test_liveness_returns_ok(client: Client) -> None:
    # 零依賴 → 永遠綠，驗證 URLconf/view/JSON wiring
    response = client.get("/healthz/")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


@pytest.mark.django_db
def test_readiness_reports_dependencies_ok(client: Client) -> None:
    response = client.get("/readyz/")
    assert response.status_code == 200
    assert response.json()["checks"] == {"database": "ok", "cache": "ok"}
```

> 使用 pytest-django 提供的 `client` fixture，而非自行 `Client()`——它會自動處理 test DB 的建立 / 回收。

---

## 3. 執行測試

```bash
# 全部測試（需要 db + redis，勿加 --no-deps）
docker compose run --rm web pytest -q

# 只跑純領域測試（無 DB，極快）
docker compose run --rm --no-deps web pytest apps/health/tests.py -q

# 跑單一 app
docker compose run --rm web pytest apps/health -q

# 跑單一測試函式
docker compose run --rm web pytest apps/health/tests.py::test_compute_bmi_basic -q

# 顯示詳細輸出
docker compose run --rm web pytest -v

# 遇第一個失敗即停
docker compose run --rm web pytest -x
```

目前測試數：**4 passed**（2 純領域 + 2 整合）。

---

## 4. 測試資料工廠（M1.5 規劃）

M1.5 起以 factory_boy 建立測試資料，取代手刻 fixture：

```python
# 規劃示意
import factory
from apps.accounts.models import User, UserProfile

class UserFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = User
    username = factory.Sequence(lambda n: f"user{n}")

class UserProfileFactory(factory.django.DjangoModelFactory):
    class Meta:
        model = UserProfile
    user = factory.SubFactory(UserFactory)
    height_cm = 170
```

---

## 5. 測試策略（後續里程碑）

| 層 | 測試重點 | 是否需 DB |
| --- | --- | --- |
| Domain | 公式、邊界值、例外（如 `compute_bmi` 對 height ≤ 0 拋錯） | 否 |
| Application（service） | 用例正確性、交易回滾、驗證 | 是 |
| Application（selector） | 查詢正確、N+1 防護、跨實體組裝 | 是 |
| Interface（API） | 狀態碼、序列化、權限、認證 | 是 |

**Coverage 目標**：≥ 80%（規劃以 `pytest-cov` 量測並納入 CI 門檻）。

```bash
# 規劃（加入 pytest-cov 後）
docker compose run --rm web pytest --cov=apps --cov=core --cov-report=term-missing
```

CI 如何執行測試見 [code_quality.md](code_quality.md) 與 [deployment.md](deployment.md)。
