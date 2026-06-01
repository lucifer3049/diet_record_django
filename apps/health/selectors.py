from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal

from apps.accounts.models import User
from apps.health.domain import BMICategory, classify_bmi, compute_bmi
from apps.health.models import HealthRecord


@dataclass(frozen=True, slots=True)
class BMIResult:
    """跨實體計算結果的 value object：對外契約，與 ORM 解耦。"""

    value: Decimal
    category: BMICategory
    weight_kg: Decimal
    height_cm: Decimal

@dataclass(frozen=True, slots=True)
class WeightPoint:
    recorded_at: str
    weight_kg: Decimal


def latest_bmi(user: User) -> BMIResult | None:
    """
    組裝 BMI: 身高來自 Profile，體重來自 HealthRecord。
    回傳 None 的情況:尚未填身高，或還沒有任何量測記錄
    這是BMI不放model的理由，他需要查兩張表，是application的職責
    """
    height_cm: Decimal | None = getattr(user.profile, "height_cm", None)
    if height_cm is None:
        return None

    record = HealthRecord.objects.for_user(user).most_recent_first().first()
    if record is None:
        return None

    bmi = compute_bmi(record.weight_kg, height_cm)
    return BMIResult(
        value=bmi,
        category=classify_bmi(bmi),
        weight_kg=record.weight_kg,
        height_cm=height_cm,
    )

def weight_trend(user: User, *, limit: int = 90) -> list[WeightPoint]:
    """
    體重趨勢(時間升序)。用.values()只取需要的欄位，避免拉整個model
    """
    rows = (
        HealthRecord.objects.for_user(user)
        .chronological()
        .values("recorded_at", "weight_kg")[:limit]
    )
    return [
        WeightPoint(recorded_at=r["recorded_at"].isoformat(), weight_kg=r["weight_kg"])
        for r in rows
    ]
