from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import User, UserProfile

admin.site.register(User, UserAdmin)


@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ("user", "gender", "height_cm", "activity_level", "health_goal")
    search_fields = ("user__username",)
