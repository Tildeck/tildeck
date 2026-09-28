from unittest.mock import patch

from app.config import get_app_version
from app.protocol import PROTOCOL_VERSION


async def test_liveness(client):
    response = await client.get("/api/health/live")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


async def test_readiness_checks_the_database(client):
    response = await client.get("/api/health/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "database": "ok", "error": None}


async def test_readiness_reports_an_unreachable_database_with_a_stable_code(client):
    class Broken:
        def connect(self):
            raise ConnectionRefusedError("database is down")

    with patch("app.routers.health.db.engine", Broken()):
        response = await client.get("/api/health/ready")
    assert response.status_code == 503
    assert response.json() == {"status": "error", "database": "error", "error": "database_unavailable"}


async def test_server_info(client):
    response = await client.get("/api/info")
    assert response.status_code == 200
    assert response.json() == {"name": "tildeck", "version": get_app_version(), "protocol_version": PROTOCOL_VERSION}


async def test_unknown_api_path_is_404_even_with_a_panel(client):
    response = await client.get("/api/does-not-exist")
    assert response.status_code == 404
