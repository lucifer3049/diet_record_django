from decimal import Decimal

import pytest
from django.utils import timezone

from apps.accounts.models import User, UserProfile
from apps.health.domain import BMICategory
from apps.health.selectors import latest_bmi, weight_trend
from apps.health.services import (
    HealthValidationError,
    MeasurementInput,
    record_measurement,
)


@pytest.fixture
def user(db: None) -> User:
    u = User.objects.create_user(username="alice", password="x")
    UserProfile.objects.create(user=u, height_cm=Decimal("170"))
    return u


@pytest.mark.django_db
def test_record_measurement_persists(user: User) -> None:
    rec = record_measurement(user, MeasurementInput(weight_kg=Decimal("70")))
    assert rec.pk is not None
    assert rec.weight_kg == Decimal("70")


@pytest.mark.django_db
def test_record_measurement_rejects_nonpositive_weight(user: User) -> None:
    with pytest.raises(HealthValidationError):
        record_measurement(user, MeasurementInput(weight_kg=Decimal("0")))


@pytest.mark.django_db
def test_latest_bmi_assembles_across_entities(user: User) -> None:
    record_measurement(user, MeasurementInput(weight_kg=Decimal("70")))
    result = latest_bmi(user)
    assert result is not None
    assert result.value == Decimal("24.2")       
    assert result.category is BMICategory.OVERWEIGHT

@pytest.mark.django_db
def test_latest_bmi_none_without_height(db: None) -> None:
    u = User.objects.create_user(username="bob", password="x")
    UserProfile.objects.create(user=u)            # 沒填身高
    record_measurement(u, MeasurementInput(weight_kg=Decimal("70")))
    assert latest_bmi(u) is None


@pytest.mark.django_db
def test_weight_trend_is_chronological(user: User) -> None:
    now = timezone.now()
    for w in ("70", "69", "68"):
        record_measurement(user, MeasurementInput(weight_kg=Decimal(w), recorded_at=now))
    trend = weight_trend(user)
    assert [p.weight_kg for p in trend] == [Decimal("70"), Decimal("69"), Decimal("68")]

