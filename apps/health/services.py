from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from decimal import Decimal

from django.db import transaction
from django.utils import timezone

from apps.accounts.models import User
from apps.health.models import HealthRecord


class HealthValidationError(Exception):
    """
    領域層級的驗證錯誤;由 interface層轉成適當的HTTP response
    """

@dataclass(frozen=True, slots=True)
class MeasurementInput:
    weight_kg: Decimal
    body_fat_pct: Decimal | None = None
    waist_cm: Decimal | None = None
    recorded_at: datetime | None = None

def record_measurement(user: User, data: MeasurementInput) -> HealthRecord:
    """
    新增一筆量測記錄。
    這裡驗證體重和體脂是否合法，在決定紀錄時間，最後在資料庫交易中建立一筆HealthRecord，並回傳建立完成的資料。
    """
    if data.weight_kg <= 0:
        raise HealthValidationError("weight_kg 必須大於 0")
    if data.body_fat_pct is not None and not (0 <= data.body_fat_pct <= 100):
        raise HealthValidationError("body_fat_pct 必須在 0 到 100 之間")
    
    recorded_at = data.recorded_at or timezone.now()

    with transaction.atomic():
        return HealthRecord.objects.create(
            user=user,
            weight_kg=data.weight_kg,
            body_fat_pct=data.body_fat_pct,
            waist_cm=data.waist_cm,
            recorded_at=recorded_at,
        )
