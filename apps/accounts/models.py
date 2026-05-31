from __future__ import annotations

from datetime import date

from django.contrib.auth.models import AbstractUser
from django.db import models


class User(AbstractUser):
    def __str__(self) -> str:
        return self.username


class UserProfile(models.Model):
    class Gender(models.TextChoices):
        MALE = "male", "Male"
        FEMALE = "female", "Female"
        OTHER = "other", "Other"

    class ActivityLevel(models.TextChoices):
        SEDENTARY = "sedentary", "Sedentary"
        LIGHT = "light", "Lightly active"
        MODERATE = "moderate", "Moderately active"
        ACTIVE = "active", "Very active"

    class HealthGoal(models.TextChoices):
        LOSE_FAT = "lose_fat", "Lose fat"
        GAIN_MUSCLE = "gain_muscle", "Gain muscle"
        MAINTAIN = "maintain", "Maintain"

    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name="profile")
    gender = models.CharField(max_length=10, choices=Gender.choices, blank=True)
    birth_date = models.DateField(null=True, blank=True)
    height_cm = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True)
    activity_level = models.CharField(max_length=12, choices=ActivityLevel.choices, blank=True)
    health_goal = models.CharField(max_length=12, choices=HealthGoal.choices, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return f"{self.user.username}>"

    @property
    def age(self) -> int | None:
        """單一實體、純計算 → 放 model 合理（對比 BMI 的跨實體，見 health/domain.py)。"""
        if self.birth_date is None:
            return None
        today = date.today()
        before_birthday = (today.month, today.day) < (self.birth_date.month, self.birth_date.day)
        return today.year - self.birth_date.year - int(before_birthday)
