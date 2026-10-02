"""The admin API against a real PostgreSQL: first-run setup with the one-time
token, password and TOTP sign-in, sessions with CSRF, and the users, devices,
settings, and activity an administrator manages."""

import asyncio
import time
import uuid
from datetime import timedelta

import pyotp
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text

from app import accounts, admins, clock
from app.db import engine
from app.main import app
from app.routers import account as account_routes
from app.routers import admin as admin_routes
from tests.test_accounts import (  # noqa: F401 - mail is a fixture
    CountingHasher,
    H,
    Keys,
    b64,
    bearer,
    mail,
    register,
    verify,
)

USERNAME = "operator"
PASSWORD = "a-long-admin-password"


@pytest.fixture
async def panel():
    # The session cookie is Secure: it only comes back over https.
    async with AsyncClient(transport=ASGITransport(app=app), base_url="https://test") as c:
        yield c


@pytest.fixture(autouse=True)
async def clean():
    account_routes.limiter.reset()
    admin_routes.limiter.reset()
    yield
    admins.setup.close()
    async with engine.begin() as conn:
        for table in (
            "admin_sessions",
            "admins",
            "records",
            "email_tokens",
            "devices",
            "accounts",
            "settings",
            "audit_entries",
        ):
            await conn.execute(text(f"DELETE FROM {table}"))


class Authenticator:
    """The administrator's phone: codes for the current, or a later, step."""

    def __init__(self, secret: str, monkeypatch):
        self.totp = pyotp.TOTP(secret)
        self.now = time.time()
        monkeypatch.setattr(admins, "_now", lambda: self.now)

    def code(self) -> str:
        return self.totp.at(self.now)

    def next(self) -> str:
        self.now += self.totp.interval
        return self.code()


async def set_up(panel, monkeypatch) -> tuple[dict, Authenticator]:
    token = admins.setup.issue()
    start = await panel.post(
        "/api/admin/setup/start", json={"setup_token": token, "username": USERNAME, "password": PASSWORD}
    )
    assert start.status_code == 200, start.text
    phone = Authenticator(start.json()["secret"], monkeypatch)
    done = await panel.post("/api/admin/setup/complete", json={"setup_token": token, "code": phone.code()})
    assert done.status_code == 200, done.text
    return {"X-CSRF-Token": done.json()["csrf_token"]}, phone


async def test_the_first_administrator_needs_the_setup_token_and_a_working_second_factor(panel, monkeypatch):
    assert (await panel.get("/api/admin/setup")).json() == {"needed": True}
    token = admins.setup.issue()
    body = {"setup_token": "not-the-token", "username": USERNAME, "password": PASSWORD}
    res = await panel.post("/api/admin/setup/start", json=body)
    assert (res.status_code, res.json()) == (403, {"error": "invalid_setup_token"})

    start = await panel.post("/api/admin/setup/start", json={**body, "setup_token": token})
    enrollment = start.json()
    assert enrollment["uri"].startswith("otpauth://totp/Tildeck:operator?")
    assert enrollment["qr_image"].startswith("data:image/svg+xml")

    # No administrator exists until a code from the new secret is confirmed.
    wrong = await panel.post("/api/admin/setup/complete", json={"setup_token": token, "code": "000000"})
    assert (wrong.status_code, wrong.json()) == (401, {"error": "invalid_totp"})
    assert (await panel.get("/api/admin/setup")).json() == {"needed": True}

    phone = Authenticator(enrollment["secret"], monkeypatch)
    done = await panel.post("/api/admin/setup/complete", json={"setup_token": token, "code": phone.code()})
    assert done.status_code == 200 and done.json()["username"] == USERNAME
    cookie = done.headers["set-cookie"].lower()
    for flag in ("httponly", "secure", "samesite=strict", "path=/api/admin"):
        assert flag in cookie
    assert (await panel.get("/api/admin/session")).json()["username"] == USERNAME

    # Once there is an administrator, setup is closed for good.
    assert (await panel.get("/api/admin/setup")).json() == {"needed": False}
    again = await panel.post("/api/admin/setup/start", json={**body, "setup_token": token})
    assert (again.status_code, again.json()) == (409, {"error": "setup_not_needed"})


async def test_sign_in_needs_the_password_and_an_unused_code(panel, monkeypatch):
    csrf, phone = await set_up(panel, monkeypatch)
    await panel.delete("/api/admin/session", headers=csrf)
    assert (await panel.get("/api/admin/session")).status_code == 401

    def attempt(password: str, code: str):
        return panel.post("/api/admin/session", json={"username": USERNAME, "password": password, "code": code})

    # The setup code was used: the same step is refused, like a wrong password.
    replay = await attempt(PASSWORD, phone.code())
    wrong_password = await attempt("not-the-password", phone.next())
    assert (replay.status_code, replay.json()) == (401, {"error": "invalid_credentials"})
    assert (wrong_password.status_code, wrong_password.json()) == (401, {"error": "invalid_credentials"})

    ok = await attempt(PASSWORD, phone.next())
    assert ok.status_code == 200
    assert (await attempt(PASSWORD, phone.code())).status_code == 401, "a code works once"

    log = (await panel.get("/api/admin/activity")).json()["entries"]
    actions = [e["action"] for e in log]
    assert actions[:4] == ["admin_signin_failed", "admin_signin", "admin_signin_failed", "admin_signin_failed"]


async def test_an_unknown_administrator_takes_as_long_as_a_wrong_password(panel, monkeypatch):
    await set_up(panel, monkeypatch)
    verified = []
    monkeypatch.setattr(accounts, "_hasher", CountingHasher(accounts._hasher, verified))
    res = await panel.post("/api/admin/session", json={"username": "nobody", "password": PASSWORD, "code": "000000"})
    assert res.status_code == 401
    assert len(verified) == 1


async def test_admin_attempts_sent_at_once_cannot_get_past_the_limit(panel, monkeypatch):
    await set_up(panel, monkeypatch)
    body = {"username": USERNAME, "password": "not-the-password", "code": "000000"}
    answers = await asyncio.gather(*(panel.post("/api/admin/session", json=body) for _ in range(15)))
    assert sorted(a.status_code for a in answers) == [401] * 10 + [429] * 5


async def test_changes_need_the_csrf_token_and_sessions_expire(panel, monkeypatch):
    csrf, _ = await set_up(panel, monkeypatch)
    change = {"values": {"registration_mode": "invite"}}
    res = await panel.put("/api/admin/settings", json=change)
    assert (res.status_code, res.json()) == (403, {"error": "csrf_failed"})
    res = await panel.put("/api/admin/settings", json=change, headers={"X-CSRF-Token": "forged"})
    assert res.status_code == 403
    assert (await panel.put("/api/admin/settings", json=change, headers=csrf)).status_code == 204
    assert (await panel.get("/api/admin/settings")).status_code == 200

    later = clock.now() + timedelta(minutes=31)
    monkeypatch.setattr(clock, "now", lambda: later)
    assert (await panel.get("/api/admin/settings")).status_code == 401


async def test_nothing_is_open_without_a_session(panel):
    for method, path in [
        ("GET", "/api/admin/users"),
        ("GET", "/api/admin/settings"),
        ("GET", "/api/admin/activity"),
        ("POST", f"/api/admin/devices/{uuid.uuid4()}/revoke"),
        ("DELETE", f"/api/admin/users/{uuid.uuid4()}"),
    ]:
        res = await panel.request(method, path)
        assert (res.status_code, res.json()) == (401, {"error": "unauthorized"}), path


async def test_administrators_see_metadata_and_manage_accounts(panel, client, mail, monkeypatch):  # noqa: F811
    csrf, _ = await set_up(panel, monkeypatch)
    keys = Keys("user@example.test")
    token = await register(client, keys)
    await verify(client, mail, keys)
    change = {"id": str(uuid.uuid4()), "version": 1, "deleted": False, "nonce": b64(24), "ct": b64(300)}
    assert (
        await client.post("/api/sync/records", json={"changes": [change]}, headers=bearer(token))
    ).status_code == 200

    [user] = (await panel.get("/api/admin/users")).json()
    assert user["email"] == "user@example.test" and user["email_verified"] is True
    assert (user["devices"], user["records"], user["storage_bytes"]) == (1, 1, len(change["ct"]))
    detail = (await panel.get(f"/api/admin/users/{user['id']}")).json()
    body = str(detail)
    for secret in (keys.auth_key, keys.wrap_pw["ct"], keys.wrap_rk["ct"], change["ct"], keys.kdf["salt"]):
        assert secret not in body, "the panel never receives keys, wraps, or ciphertext"

    # Disabled: the devices stop syncing at once, and come back when enabled.
    assert (await panel.post(f"/api/admin/users/{user['id']}/disable", headers=csrf)).status_code == 204
    res = await client.get("/api/sync/records", headers=bearer(token))
    assert (res.status_code, res.json()) == (403, {"error": "account_disabled"})
    assert (await panel.post(f"/api/admin/users/{user['id']}/enable", headers=csrf)).status_code == 204
    assert (await client.get("/api/sync/records", headers=bearer(token))).status_code == 200

    # A revoked device is told by email, as when the user removes it.
    [device] = detail["device_list"]
    assert (await panel.post(f"/api/admin/devices/{device['id']}/revoke", headers=csrf)).status_code == 204
    assert (await client.get("/api/sync/records", headers=bearer(token))).status_code == 401
    assert any("removed" in m.subject for m in mail.sent)

    assert (await panel.delete(f"/api/admin/users/{user['id']}", headers=csrf)).status_code == 204
    assert (await panel.get("/api/admin/users")).json() == []
    log = [(e["action"], e["source"], e["actor"]) for e in (await panel.get("/api/admin/activity")).json()["entries"]]
    for action in ("account_deleted", "device_revoked", "account_enabled", "account_disabled"):
        assert (action, "admin", USERNAME) in log


async def test_settings_show_where_values_come_from_and_never_a_secret(panel, monkeypatch):
    csrf, _ = await set_up(panel, monkeypatch)
    secret = "smtp-password-that-must-stay-inside"

    async def save(**values):
        return await panel.put("/api/admin/settings", json={"values": values}, headers=csrf)

    assert (await save(smtp_password=secret, smtp_host="mail.example.test")).status_code == 204
    monkeypatch.setenv("PUBLIC_URL", "https://sync.example.test")
    res = await save(public_url="https://other.test")
    assert (res.status_code, res.json()) == (409, {"error": "setting_locked", "key": "public_url"})
    unknown = await save(nope="x")
    assert (unknown.status_code, unknown.json()) == (404, {"error": "not_found", "key": "nope"})

    # One refused value saves nothing of the page.
    bad = await save(smtp_host="changed.example.test", smtp_port="not-a-port")
    assert (bad.status_code, bad.json()) == (422, {"error": "invalid_request", "key": "smtp_port"})
    rows = {r["key"]: r for r in (await panel.get("/api/admin/settings")).json()}
    assert rows["smtp_host"]["value"] == "mail.example.test"

    assert rows["smtp_password"]["configured"] is True and rows["smtp_password"]["value"] is None
    assert rows["public_url"]["locked"] is True and rows["public_url"]["origin"] == "env"
    everything = (await panel.get("/api/admin/settings")).text + (await panel.get("/api/admin/activity")).text
    assert secret not in everything


async def test_an_invitation_registers_one_address_once_and_confirms_it(panel, client, monkeypatch):
    csrf, _ = await set_up(panel, monkeypatch)
    # Invitations need no email: this server has none configured.
    monkeypatch.setenv("REGISTRATION_MODE", "invite")
    res = await panel.post("/api/admin/invites", json={"email": "Guest@Example.test"}, headers=csrf)
    assert res.status_code == 201 and res.json()["emailed"] is False
    code = res.json()["code"]

    uninvited = Keys("other@example.test")
    refused = await client.post("/api/account/register", json=uninvited.register_body(), headers=H)
    assert (refused.status_code, refused.json()) == (403, {"error": "registration_invite_required"})
    wrong_address = await client.post(
        "/api/account/register", json={**uninvited.register_body(), "invite_code": code}, headers=H
    )
    assert (wrong_address.status_code, wrong_address.json()) == (403, {"error": "invalid_invite"})

    guest = Keys("guest@example.test")
    ok = await client.post("/api/account/register", json={**guest.register_body(), "invite_code": code}, headers=H)
    assert ok.status_code == 201 and ok.json()["email_verified"] is True
    # Confirmed by the invitation: the device syncs at once.
    assert (await client.get("/api/sync/records", headers=bearer(ok.json()["device_token"]))).status_code == 200

    again = Keys("guest@example.test")
    reused = await client.post("/api/account/register", json={**again.register_body(), "invite_code": code}, headers=H)
    assert reused.status_code in (403, 409)
    [row] = (await panel.get("/api/admin/invites")).json()
    assert row["status"] == "used" and row["email"] == "guest@example.test"
    assert "code" not in row, "the code is shown once, at creation"


async def test_revoked_and_expired_invitations_are_refused(panel, client, monkeypatch):
    csrf, _ = await set_up(panel, monkeypatch)
    monkeypatch.setenv("REGISTRATION_MODE", "invite")

    async def invite(email: str) -> dict:
        res = await panel.post("/api/admin/invites", json={"email": email}, headers=csrf)
        return res.json()

    revoked = await invite("a@example.test")
    assert (await panel.post(f"/api/admin/invites/{revoked['id']}/revoke", headers=csrf)).status_code == 204
    body = {**Keys("a@example.test").register_body(), "invite_code": revoked["code"]}
    assert (await client.post("/api/account/register", json=body, headers=H)).json() == {"error": "invalid_invite"}

    expired = await invite("b@example.test")
    later = clock.now() + timedelta(days=8)
    monkeypatch.setattr(clock, "now", lambda: later)
    body = {**Keys("b@example.test").register_body(), "invite_code": expired["code"]}
    assert (await client.post("/api/account/register", json=body, headers=H)).json() == {"error": "invalid_invite"}


async def test_an_invitation_is_emailed_when_email_is_configured(panel, client, mail, monkeypatch):  # noqa: F811
    csrf, _ = await set_up(panel, monkeypatch)
    res = await panel.post("/api/admin/invites", json={"email": "guest@example.test", "locale": "he"}, headers=csrf)
    assert res.json()["emailed"] is True
    [message] = [m for m in mail.sent if m.to == "guest@example.test"]
    assert res.json()["code"] in message.body and "Tildeck" in message.subject
    taken = await panel.post("/api/admin/invites", json={"email": "guest@example.test"}, headers=csrf)
    assert taken.status_code == 201, "an open invitation does not block another"
    keys = Keys("user@example.test")
    await register(client, keys)
    exists = await panel.post("/api/admin/invites", json={"email": "user@example.test"}, headers=csrf)
    assert (exists.status_code, exists.json()) == (409, {"error": "email_taken"})
