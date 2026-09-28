"""The static admin panel: files as they are, the app shell for client-side
routes, and never a panel answer for an /api path."""

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from app import panel


@pytest.fixture
async def panel_client(tmp_path):
    root = tmp_path / "panel"
    (root / "_nuxt").mkdir(parents=True)
    (root / "index.html").write_text("<html>shell</html>")
    (root / "_nuxt" / "entry.abc123.js").write_text("console.log(1)")
    (tmp_path / "outside.txt").write_text("secret")

    app = FastAPI()

    @app.get("/api/real")
    async def real() -> dict:
        return {"ok": True}

    assert panel.mount(app, str(root))
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c


async def test_client_route_gets_the_shell(panel_client):
    res = await panel_client.get("/users/42")
    assert res.status_code == 200
    assert res.text == "<html>shell</html>"
    assert res.headers["cache-control"] == "no-cache"
    assert res.headers["x-content-type-options"] == "nosniff"


async def test_hashed_asset_is_cached_forever(panel_client):
    res = await panel_client.get("/_nuxt/entry.abc123.js")
    assert res.status_code == 200
    assert "immutable" in res.headers["cache-control"]


async def test_head_is_answered(panel_client):
    res = await panel_client.head("/")
    assert res.status_code == 200


async def test_api_paths_never_fall_back(panel_client):
    assert (await panel_client.get("/api/real")).json() == {"ok": True}
    assert (await panel_client.get("/api/missing")).status_code == 404
    assert (await panel_client.get("/api")).status_code == 404


async def test_no_file_outside_the_panel_is_served(panel_client):
    res = await panel_client.get("/../outside.txt")
    assert "secret" not in res.text
    res = await panel_client.get("/%2e%2e/outside.txt")
    assert "secret" not in res.text


def test_missing_panel_serves_api_only(tmp_path):
    assert panel.mount(FastAPI(), str(tmp_path / "absent")) is False
