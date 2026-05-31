from django.contrib import admin
from django.urls import path

from core.healthcheck import liveness, readiness

urlpatterns = [
    path("admin/", admin.site.urls),
    path("healthz/", liveness),
    path("readyz/", readiness),
]
