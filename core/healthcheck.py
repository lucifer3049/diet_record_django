from __future__ import annotations

from django.core.cache import cache
from django.db import connection
from django.http import HttpRequest, JsonResponse


def liveness(request: HttpRequest) -> JsonResponse:
    """程序活著就回 200（k8s liveness probe 用）。"""
    return JsonResponse({"status": "ok"})


def readiness(request: HttpRequest) -> JsonResponse:
    """相依資源(DB / cache)可用才回 200，否則 503（readiness probe 用）。"""
    checks: dict[str, str] = {}
    healthy = True
    try:
        with connection.cursor() as cur:
            cur.execute("SELECT 1")
        checks["database"] = "ok"
    except Exception:
        checks["database"] = "error"
        healthy = False
    try:
        cache.set("__readiness__", "1", timeout=5)
        ok = cache.get("__readiness__") == "1"
        checks["cache"] = "ok" if ok else "error"
        healthy = healthy and ok
    except Exception:
        checks["cache"] = "error"
        healthy = False
    return JsonResponse(
        {"status": "ok" if healthy else "degraded", "checks": checks},
        status=200 if healthy else 503,
    )
