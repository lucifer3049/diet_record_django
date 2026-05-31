from __future__ import annotations

from decimal import Decimal
from enum import Enum


class BMICategory(Enum):
    UNDERWEIGHT = "underweight"
    NORMAL = "normal"
    OVERWEIGHT = "overweight"
    OBESE = "obese"


def compute_bmi(weight_kg: Decimal, height_cm: Decimal) -> Decimal:
    """BMI = 體重 / 身高^2。純函式:不碰 DB 不碰框架 -> 可即時單元測試"""
    if height_cm <= 0:
        raise ValueError("height_cm 必須為整數且大於 0")
    height_m = height_cm / Decimal("100")
    return (weight_kg / (height_m * height_m)).quantize(Decimal("0.1"))


def classify_bmi(bmi: Decimal) -> BMICategory:
    """臺灣國建署 / 亞洲成人切點。集中在此處，便於日後調整"""
    if bmi < Decimal("18.5"):
        return BMICategory.UNDERWEIGHT
    if bmi < Decimal("24"):
        return BMICategory.NORMAL
    if bmi < Decimal("27"):
        return BMICategory.OVERWEIGHT
    return BMICategory.OBESE
