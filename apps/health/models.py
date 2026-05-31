from __future__ import annotations

from typing import TYPE_CHECKING

from django.conf import settings
from django.db import models

if TYPE_CHECKING:
    from apps.accounts.models import User


class HealthRecordQuerySet(models.QuerySet["HealthRecord"]):
    """自訂 QuerySet，提供更語意化的查詢方法"""

    def for_user(self, user: User) -> HealthRecordQuerySet:
        return self.filter(user=user)

    def chronological(self) -> HealthRecordQuerySet:
        return self.order_by("recorded_at")

    def most_recent_first(self) -> HealthRecordQuerySet:
        return self.order_by("-recorded_at")


class HealthRecord(models.Model):
    """使用者紀錄自己的健康數據，如體重、體脂肪率、腰圍"""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="health_records",
        verbose_name="使用者",
    )
    weight_kg = models.DecimalField(verbose_name="體重", max_digits=5, decimal_places=2)
    body_fat_pct = models.DecimalField(
        verbose_name="體脂肪率", max_digits=4, decimal_places=1, null=True, blank=True
    )
    waist_cm = models.DecimalField(
        verbose_name="腰圍", max_digits=5, decimal_places=2, null=True, blank=True
    )
    recorded_at = models.DateTimeField(verbose_name="測量時間")
    created_at = models.DateTimeField(verbose_name="建立時間", auto_now_add=True)

    objects = HealthRecordQuerySet.as_manager()

    class Meta:
        ordering = ["-recorded_at"]
        indexes = [models.Index(fields=["user", "recorded_at"])]

    def __str__(self) -> str:
        return f"{self.user_id} @ {self.recorded_at:%Y-%m-%d}: {self.weight_kg}kg"
