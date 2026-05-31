from __future__ import annotations

import pytest
from django.test import Client


def test_liveness_returns_ok(client: Client) -> None:
    """liveness 不依賴任何外部資源 → 永遠綠，是『app 有正確接起來』的最基本訊號。"""
    response = client.get("/healthz/")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


@pytest.mark.django_db
def test_readiness_reports_dependencies_ok(client: Client) -> None:
    """readiness 需要 DB + cache 可用；CI 與 compose 都會提供，屬整合層 smoke。"""
    response = client.get("/readyz/")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["checks"] == {"database": "ok", "cache": "ok"}
