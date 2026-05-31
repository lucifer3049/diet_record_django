# 單元測試:測試 BMI 計算的邏輯
from decimal import Decimal

from apps.health.domain import BMICategory, classify_bmi, compute_bmi


def test_compute_bmi_basic() -> None:
    # 170cm / 70kg → 24.2（純計算，無 DB、毫秒級）
    assert compute_bmi(Decimal("70"), Decimal("170")) == Decimal("24.2")


def test_classify_bmi_taiwan_cutoffs() -> None:
    assert classify_bmi(Decimal("18.4")) is BMICategory.UNDERWEIGHT
    assert classify_bmi(Decimal("23.9")) is BMICategory.NORMAL
    assert classify_bmi(Decimal("26.9")) is BMICategory.OVERWEIGHT
    assert classify_bmi(Decimal("27.0")) is BMICategory.OBESE
