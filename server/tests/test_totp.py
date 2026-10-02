"""Two-factor sign-in for user accounts (docs/security-model.md, "Two-factor
sign-in"), against a real PostgreSQL."""

import time

import pyotp
from sqlalchemy import text

from app import admins
from app.db import engine
from tests.test_accounts import H, Keys, b64, bearer, clean, device, mail, register  # noqa: F401 - fixtures


class Phone:
    """The user's authenticator app, with a clock the server shares."""

    def __init__(self, secret: str, monkeypatch):
        self.totp = pyotp.TOTP(secret)
        self.now = time.time()
        monkeypatch.setattr(admins, "_now", lambda: self.now)

    def code(self) -> str:
        return self.totp.at(self.now)

    def next(self) -> str:
        self.now += self.totp.interval
        return self.code()


async def turn_on(client, token: str, monkeypatch) -> Phone:
    start = await client.post("/api/account/totp/start", headers=bearer(token))
    assert start.status_code == 200, start.text
    enrollment = start.json()
    assert enrollment["uri"].startswith("otpauth://totp/Tildeck:")
    assert enrollment["qr_image"].startswith("data:image/svg+xml")
    phone = Phone(enrollment["secret"], monkeypatch)
    done = await client.post("/api/account/totp/confirm", json={"code": phone.code()}, headers=bearer(token))
    assert done.status_code == 204, done.text
    return phone


async def test_turning_it_on_needs_a_code_from_the_new_secret(client, mail, monkeypatch):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    assert (await client.get("/api/account", headers=bearer(token))).json()["totp_enabled"] is False

    start = (await client.post("/api/account/totp/start", headers=bearer(token))).json()
    wrong = await client.post("/api/account/totp/confirm", json={"code": "000000"}, headers=bearer(token))
    assert (wrong.status_code, wrong.json()) == (401, {"error": "invalid_totp"})
    assert (await client.get("/api/account", headers=bearer(token))).json()["totp_enabled"] is False

    phone = Phone(start["secret"], monkeypatch)
    ok = await client.post("/api/account/totp/confirm", json={"code": phone.code()}, headers=bearer(token))
    assert ok.status_code == 204
    assert (await client.get("/api/account", headers=bearer(token))).json()["totp_enabled"] is True
    assert any("Two-factor sign-in is on" in m.subject for m in mail.sent)
    again = await client.post("/api/account/totp/start", headers=bearer(token))
    assert (again.status_code, again.json()) == (409, {"error": "totp_already_enabled"})


async def test_sign_in_needs_the_code_and_a_code_works_once(client, mail, monkeypatch):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    phone = await turn_on(client, token, monkeypatch)
    body = {"email": keys.email, "auth_key": keys.auth_key, "device": keys.device}

    def signin(**extra):
        return client.post("/api/account/signin", json={**body, **extra}, headers=H)

    # The right key without a code: the client asks for one.
    res = await signin()
    assert (res.status_code, res.json()) == (401, {"error": "totp_required"})
    # A wrong key never says whether a code is needed.
    res = await signin(auth_key=b64(32))
    assert (res.status_code, res.json()) == (401, {"error": "invalid_credentials"})
    res = await signin(totp_code="000000")
    assert (res.status_code, res.json()) == (401, {"error": "invalid_credentials"})

    code = phone.next()
    assert (await signin(totp_code=code)).status_code == 200
    replay = await signin(totp_code=code)
    assert (replay.status_code, replay.json()) == (401, {"error": "invalid_credentials"}), "a code works once"
    # Signing in with the code does not use up the limit.
    for _ in range(12):
        assert (await signin(totp_code=phone.next())).status_code == 200


async def test_devices_stay_signed_in_when_it_is_turned_on(client, mail, monkeypatch):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    await turn_on(client, token, monkeypatch)
    assert (await client.get("/api/account", headers=bearer(token))).status_code == 200


async def test_changing_the_master_password_needs_the_code(client, mail, monkeypatch):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    phone = await turn_on(client, token, monkeypatch)
    new = {"kdf": keys.kdf, "auth_key": b64(32), "wrap_pw": {"nonce": b64(24), "ct": b64(48)}}
    body = {"auth_key": keys.auth_key, "new": new, "keep_other_devices": True}
    res = await client.post("/api/account/password", json=body, headers=bearer(token))
    assert (res.status_code, res.json()) == (401, {"error": "totp_required"})
    res = await client.post("/api/account/password", json={**body, "totp_code": phone.next()}, headers=bearer(token))
    assert res.status_code == 204, res.text


async def test_recovery_needs_the_code_at_both_steps(client, mail, monkeypatch):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    phone = await turn_on(client, token, monkeypatch)
    start = {"email": keys.email, "recovery_auth_key": keys.recovery_auth_key}
    res = await client.post("/api/account/recovery/start", json=start, headers=H)
    assert (res.status_code, res.json()) == (401, {"error": "totp_required"})

    code = phone.next()
    assert (
        await client.post("/api/account/recovery/start", json={**start, "totp_code": code}, headers=H)
    ).status_code == 200
    new = {"kdf": keys.kdf, "auth_key": b64(32), "wrap_pw": {"nonce": b64(24), "ct": b64(48)}}
    complete = {**start, "new": new, "device": device()}
    # Completing alone, without the code, is refused: it cannot skip the start's check.
    res = await client.post("/api/account/recovery/complete", json=complete, headers=H)
    assert (res.status_code, res.json()) == (401, {"error": "totp_required"})
    res = await client.post("/api/account/recovery/complete", json={**complete, "totp_code": code}, headers=H)
    assert res.status_code == 200, res.text
    # The code was spent.
    res = await client.post(
        "/api/account/recovery/complete", json={**complete, "device": device(), "totp_code": code}, headers=H
    )
    assert (res.status_code, res.json()) == (401, {"error": "recovery_failed"})


async def test_turning_it_off_needs_a_current_code(client, mail, monkeypatch):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    phone = await turn_on(client, token, monkeypatch)
    res = await client.post("/api/account/totp/disable", json={"code": "000000"}, headers=bearer(token))
    assert (res.status_code, res.json()) == (401, {"error": "invalid_totp"})
    res = await client.post("/api/account/totp/disable", json={"code": phone.next()}, headers=bearer(token))
    assert res.status_code == 204
    assert (await client.get("/api/account", headers=bearer(token))).json()["totp_enabled"] is False
    assert any("Two-factor sign-in is off" in m.subject for m in mail.sent)
    body = {"email": keys.email, "auth_key": keys.auth_key, "device": keys.device}
    assert (await client.post("/api/account/signin", json=body, headers=H)).status_code == 200

    async with engine.begin() as conn:
        actions = (await conn.execute(text("SELECT action FROM audit_entries ORDER BY id"))).scalars().all()
    assert "totp_enabled" in actions and "totp_disabled" in actions
