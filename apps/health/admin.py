from django.contrib import admin

from .models import HealthRecord


@admin.register(HealthRecord)
class HealthRecordAdmin(admin.ModelAdmin):
    """在 Django Admin 中顯示的管理資料表格設定"""

    list_display = ("user", "recorded_at", "weight_kg", "body_fat_pct", "waist_cm")
    list_filter = ("recorded_at",)
    search_fields = ("user__username",)
    date_hierarchy = "recorded_at"
