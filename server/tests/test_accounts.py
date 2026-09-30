"""Accounts and devices against a real PostgreSQL (docs/security-model.md,
"Accounts and devices"). Keys here are random stand-ins: the server treats
them as opaque bytes, exactly as it treats the real ones."""

import base64
import json
import os
import re
import secrets
import uuid
from datetime import timedelta

import pytest
from sqlalchemy import text

from app import clock, mailer
from app.db import engine
from app.main import app
from app.routers import account as account_routes

H = {"Tildeck-Protocol": "1"}


def b64(n: int) -> str:
    return base64.b64encode(secrets.token_bytes(n)).decode()


def sealed() -> dict:
    return {"nonce": b64(24), "ct": b64(48)}


def kdf() -> dict:
    return {"alg": "argon2id13", "ops": 3, "mem": 64 * 1024 * 1024, "salt": b64(16)}


def device(name: str = "Laptop") -> dict:
    return {"id": str(uuid.uuid4()), "name": name}


class Keys:
    """What a client derives and sends for one account."""

    def __init__(self, email: str, locale: str = "en"):
        self.email, self.locale = email, locale
        self.auth_key, self.recovery_auth_key = b64(32), b64(32)
        self.kdf, self.wrap_pw, self.wrap_rk = kdf(), sealed(), sealed()
        self.vault_id = str(uuid.uuid4())
        self.device = device()

    def register_body(self) -> dict:
        return {
            "email": self.email,
            "locale": self.locale,
            "vault_id": self.vault_id,
            "kdf": self.kdf,
            "auth_key": self.auth_key,
            "recovery_auth_key": self.recovery_auth_key,
            "wrap_pw": self.wrap_pw,
            "wrap_rk": self.wrap_rk,
            "device": self.device,
        }


@pytest.fixture
def mail(monkeypatch):
    """Registration open, email configured, messages captured in memory."""
    for var, value in {
        "REGISTRATION_MODE": "open",
        "SMTP_HOST": "smtp.example.test",
        "SMTP_FROM": "tildeck@example.test",
        "PUBLIC_URL": "https://sync.example.test",
    }.items():
        monkeypatch.setenv(var, value)
    memory = mailer.MemoryMailer()
    monkeypatch.setattr(app.state, "mailer", memory)
    return memory


@pytest.fixture(autouse=True)
async def clean():
    account_routes.limiter.reset()
    yield
    async with engine.begin() as conn:
        for table in ("email_tokens", "devices", "accounts"):
            await conn.execute(text(f"DELETE FROM {table}"))


def link_from(message: mailer.Mail, purpose: str) -> str:
    match = re.search(rf"https://sync\.example\.test(/links/{purpose}/\S+)", message.body)
    assert match, message.body
    return match.group(1)


async def register(client, keys: Keys) -> str:
    res = await client.post("/api/account/register", json=keys.register_body(), headers=H)
    assert res.status_code == 201, res.text
    return res.json()["device_token"]


async def verify(client, mail, keys: Keys) -> None:
    message = next(m for m in mail.sent if m.to == keys.email.lower() and "Confirm" in m.subject)
    res = await client.get(link_from(message, "verify"))
    assert res.status_code == 200


def bearer(token: str) -> dict:
    return {**H, "Authorization": f"Bearer {token}"}


async def test_the_account_api_needs_the_protocol_header_but_identity_does_not(client, mail):
    res = await client.post("/api/account/prelogin", json={"email": "a@example.test"})
    assert (res.status_code, res.json()) == (400, {"error": "unsupported_protocol"})
    res = await client.post(
        "/api/account/prelogin", json={"email": "a@example.test"}, headers={"Tildeck-Protocol": "2"}
    )
    assert res.json() == {"error": "unsupported_protocol"}
    assert (await client.get("/api/info")).status_code == 200


async def test_prelogin_does_not_reveal_which_addresses_have_accounts(client, mail):
    keys = Keys("known@example.test")
    await register(client, keys)
    known = (await client.post("/api/account/prelogin", json={"email": "KNOWN@example.test"}, headers=H)).json()
    unknown1 = (await client.post("/api/account/prelogin", json={"email": "nobody@example.test"}, headers=H)).json()
    unknown2 = (await client.post("/api/account/prelogin", json={"email": "nobody@example.test"}, headers=H)).json()
    assert known["kdf"]["salt"] == keys.kdf["salt"]
    assert unknown1 == unknown2, "an unknown address always gets the same answer"
    assert known["kdf"].keys() == unknown1["kdf"].keys()
    assert len(base64.b64decode(unknown1["kdf"]["salt"])) == 16


async def test_registration_follows_the_mode_and_needs_email(client, mail, monkeypatch):
    keys = Keys("new@example.test")
    monkeypatch.setenv("REGISTRATION_MODE", "closed")
    assert (await client.post("/api/account/register", json=keys.register_body(), headers=H)).json() == {
        "error": "registration_closed"
    }
    monkeypatch.setenv("REGISTRATION_MODE", "invite")
    assert (await client.post("/api/account/register", json=keys.register_body(), headers=H)).json() == {
        "error": "registration_invite_required"
    }
    monkeypatch.setenv("REGISTRATION_MODE", "open")
    monkeypatch.delenv("SMTP_HOST")
    assert (await client.post("/api/account/register", json=keys.register_body(), headers=H)).json() == {
        "error": "registration_needs_email"
    }


async def test_registration_signs_in_the_device_and_sends_a_verification_link(client, mail):
    keys = Keys("New@Example.test")
    token = await register(client, keys)
    me = (await client.get("/api/account", headers=bearer(token))).json()
    assert me["email"] == "new@example.test"
    assert me["email_verified"] is False
    assert [d["status"] for d in me["devices"]] == ["active"]

    await verify(client, mail, keys)
    assert (await client.get("/api/account", headers=bearer(token))).json()["email_verified"] is True

    # The link works once.
    message = next(m for m in mail.sent if "Confirm" in m.subject)
    assert (await client.get(link_from(message, "verify"))).status_code == 410

    again = await client.post("/api/account/register", json={**keys.register_body(), "device": device()}, headers=H)
    assert (again.status_code, again.json()) == (409, {"error": "email_taken"})


async def test_a_verification_link_expires(client, mail, monkeypatch):
    keys = Keys("late@example.test")
    await register(client, keys)
    later = clock.now() + timedelta(hours=25)
    monkeypatch.setattr(clock, "now", lambda: later)
    message = next(m for m in mail.sent if "Confirm" in m.subject)
    assert (await client.get(link_from(message, "verify"))).status_code == 410


async def test_wrong_credentials_look_the_same_for_known_and_unknown_addresses(client, mail):
    keys = Keys("user@example.test")
    await register(client, keys)
    for email in ("user@example.test", "nobody@example.test"):
        res = await client.post(
            "/api/account/signin", json={"email": email, "auth_key": b64(32), "device": device()}, headers=H
        )
        assert (res.status_code, res.json()) == (401, {"error": "invalid_credentials"})


async def test_a_new_device_waits_for_approval_and_only_it_can_collect_the_vault(client, mail):
    keys = Keys("user@example.test")
    first = await register(client, keys)
    await verify(client, mail, keys)

    phone = device("Phone")
    res = await client.post(
        "/api/account/signin", json={"email": keys.email, "auth_key": keys.auth_key, "device": phone}, headers=H
    )
    assert res.status_code == 202
    pending = res.json()
    assert pending["status"] == "pending" and pending["email_approval"] is True
    assert pending["signed_in"] is None, "a pending device gets no token and no vault key"

    # Before approval: nothing to collect; a wrong claim token is refused.
    claim = {"device_id": phone["id"], "claim_token": pending["claim_token"]}
    assert (await client.post("/api/devices/claim", json=claim, headers=H)).json() == {"error": "device_pending"}
    wrong = {"device_id": phone["id"], "claim_token": "not-the-token"}
    assert (await client.post("/api/devices/claim", json=wrong, headers=H)).json() == {"error": "invalid_token"}

    # Opening the emailed link only shows a page; a mail scanner cannot approve.
    approve_link = link_from(next(m for m in mail.sent if "new device" in m.subject), "approve")
    page = await client.get(approve_link)
    assert page.status_code == 200 and "Phone" in page.text and "<form" in page.text
    assert (await client.post("/api/devices/claim", json=claim, headers=H)).json() == {"error": "device_pending"}

    assert (await client.post(approve_link)).status_code == 200
    collected = await client.post("/api/devices/claim", json=claim, headers=H)
    assert collected.status_code == 200
    assert collected.json()["vault"]["wrap_pw"] == keys.wrap_pw
    assert collected.json()["vault"]["vault_id"] == keys.vault_id
    assert any("was added" in m.subject for m in mail.sent)

    # The claim token and the link are single use.
    assert (await client.post("/api/devices/claim", json=claim, headers=H)).json() == {"error": "invalid_token"}
    assert (await client.post(approve_link)).status_code == 410
    assert (await client.get("/api/account", headers=bearer(first))).status_code == 200


async def test_an_existing_device_approves_and_revokes(client, mail):
    keys = Keys("user@example.test")
    first = await register(client, keys)
    phone = device("Phone")
    pending = (
        await client.post(
            "/api/account/signin", json={"email": keys.email, "auth_key": keys.auth_key, "device": phone}, headers=H
        )
    ).json()
    assert pending["email_approval"] is False, "no approval mail for an unverified address"

    listed = (await client.get("/api/account", headers=bearer(first))).json()["devices"]
    assert {d["status"] for d in listed} == {"active", "pending"}
    assert (await client.post(f"/api/devices/{phone['id']}/approve", headers=bearer(first))).status_code == 204
    phone_token = (
        await client.post(
            "/api/devices/claim", json={"device_id": phone["id"], "claim_token": pending["claim_token"]}, headers=H
        )
    ).json()["device_token"]

    # An approved device signs in again without a new approval.
    again = await client.post(
        "/api/account/signin", json={"email": keys.email, "auth_key": keys.auth_key, "device": phone}, headers=H
    )
    assert again.status_code == 200 and again.json()["status"] == "active"
    assert again.json()["signed_in"]["vault"]["wrap_pw"] == keys.wrap_pw

    assert (await client.post(f"/api/devices/{phone['id']}/revoke", headers=bearer(first))).status_code == 204
    assert (await client.get("/api/account", headers=bearer(phone_token))).status_code == 401
    revoked = await client.post(
        "/api/account/signin", json={"email": keys.email, "auth_key": keys.auth_key, "device": phone}, headers=H
    )
    assert revoked.json() == {"error": "device_revoked"}


async def test_an_unused_device_must_sign_in_again(client, mail, monkeypatch):
    keys = Keys("idle@example.test")
    token = await register(client, keys)
    later = clock.now() + timedelta(days=91)
    monkeypatch.setattr(clock, "now", lambda: later)
    res = await client.get("/api/account", headers=bearer(token))
    assert (res.status_code, res.json()) == (401, {"error": "token_expired"})
    back = await client.post(
        "/api/account/signin", json={"email": keys.email, "auth_key": keys.auth_key, "device": keys.device}, headers=H
    )
    assert back.status_code == 200


async def test_changing_the_password_signs_out_other_devices(client, mail):
    keys = Keys("user@example.test")
    first = await register(client, keys)
    phone = device("Phone")
    pending = (
        await client.post(
            "/api/account/signin", json={"email": keys.email, "auth_key": keys.auth_key, "device": phone}, headers=H
        )
    ).json()
    await client.post(f"/api/devices/{phone['id']}/approve", headers=bearer(first))
    phone_token = (
        await client.post(
            "/api/devices/claim", json={"device_id": phone["id"], "claim_token": pending["claim_token"]}, headers=H
        )
    ).json()["device_token"]

    new = {"kdf": kdf(), "auth_key": b64(32), "wrap_pw": sealed()}
    wrong = await client.post("/api/account/password", json={"auth_key": b64(32), "new": new}, headers=bearer(first))
    assert wrong.json() == {"error": "invalid_credentials"}

    assert (
        await client.post("/api/account/password", json={"auth_key": keys.auth_key, "new": new}, headers=bearer(first))
    ).status_code == 204
    assert (await client.get("/api/account", headers=bearer(first))).status_code == 200
    assert (await client.get("/api/account", headers=bearer(phone_token))).status_code == 401
    assert (await client.post("/api/account/prelogin", json={"email": keys.email}, headers=H)).json()["kdf"][
        "salt"
    ] == new["kdf"]["salt"]
    old = await client.post(
        "/api/account/signin", json={"email": keys.email, "auth_key": keys.auth_key, "device": keys.device}, headers=H
    )
    assert old.json() == {"error": "invalid_credentials"}
    assert any("master password was changed" in m.subject for m in mail.sent)


async def test_the_recovery_key_sets_a_new_password_and_signs_out_every_device(client, mail):
    keys = Keys("user@example.test")
    first = await register(client, keys)
    body = {"email": keys.email, "recovery_auth_key": b64(32)}
    assert (await client.post("/api/account/recovery/start", json=body, headers=H)).json() == {
        "error": "recovery_failed"
    }

    started = await client.post(
        "/api/account/recovery/start", json={**body, "recovery_auth_key": keys.recovery_auth_key}, headers=H
    )
    assert started.json() == {"vault_id": keys.vault_id, "wrap_rk": keys.wrap_rk}

    new = {"kdf": kdf(), "auth_key": b64(32), "wrap_pw": sealed()}
    fresh = device("New laptop")
    done = await client.post(
        "/api/account/recovery/complete",
        json={"email": keys.email, "recovery_auth_key": keys.recovery_auth_key, "new": new, "device": fresh},
        headers=H,
    )
    assert done.status_code == 200
    assert done.json()["vault"]["wrap_pw"] == new["wrap_pw"]
    assert (await client.get("/api/account", headers=bearer(first))).status_code == 401
    assert (await client.get("/api/account", headers=bearer(done.json()["device_token"]))).status_code == 200
    assert any("recovery key was used" in m.subject for m in mail.sent)


async def test_repeated_failures_are_rate_limited(client, mail):
    keys = Keys("user@example.test")
    await register(client, keys)
    body = {"email": keys.email, "auth_key": b64(32), "device": device()}
    codes = [(await client.post("/api/account/signin", json=body, headers=H)).status_code for _ in range(11)]
    assert codes[:10] == [401] * 10 and codes[10] == 429
    right = {**body, "auth_key": keys.auth_key}
    assert (await client.post("/api/account/signin", json=right, headers=H)).json() == {"error": "rate_limited"}


async def test_a_waiting_device_may_keep_asking_but_wrong_claim_tokens_are_limited(client, mail):
    keys = Keys("user@example.test")
    await register(client, keys)
    await verify(client, mail, keys)
    phone = device("Phone")
    res = await client.post(
        "/api/account/signin", json={"email": keys.email, "auth_key": keys.auth_key, "device": phone}, headers=H
    )
    claim = {"device_id": phone["id"], "claim_token": res.json()["claim_token"]}
    for _ in range(40):
        assert (await client.post("/api/devices/claim", json=claim, headers=H)).json() == {"error": "device_pending"}

    wrong = {"device_id": phone["id"], "claim_token": "not-the-token"}
    codes = [(await client.post("/api/devices/claim", json=wrong, headers=H)).status_code for _ in range(31)]
    assert codes[0] == 401 and codes[-1] == 429


async def test_email_follows_the_account_language_and_never_carries_keys(client, mail):
    keys = Keys("hebrew@example.test", locale="he")
    await register(client, keys)
    he = json.loads(open(os.path.join(os.path.dirname(mailer.__file__), "locales", "he.json"), encoding="utf-8").read())
    message = mail.sent[-1]
    assert message.subject == he["verify_subject"]
    for secret in [keys.auth_key, keys.recovery_auth_key, keys.wrap_pw["ct"], keys.wrap_rk["ct"], keys.kdf["salt"]]:
        assert all(secret not in m.body and secret not in m.subject for m in mail.sent)


async def test_mail_goes_out_over_smtp(client, mail, monkeypatch):
    """The real smtplib path, against a local SMTP server without TLS."""
    from aiosmtpd.controller import Controller

    class Collect:
        def __init__(self):
            self.messages = []

        async def handle_DATA(self, server, session, envelope):
            self.messages.append(envelope)
            return "250 OK"

    handler = Collect()
    import socket

    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    controller = Controller(handler, hostname="127.0.0.1", port=port)
    controller.start()
    try:
        monkeypatch.setenv("SMTP_HOST", "127.0.0.1")
        monkeypatch.setenv("SMTP_PORT", str(port))
        monkeypatch.setenv("SMTP_SECURITY", "none")
        monkeypatch.setattr(app.state, "mailer", mailer.SmtpMailer())
        await register(client, Keys("smtp@example.test"))
        assert len(handler.messages) == 1
        envelope = handler.messages[0]
        assert envelope.rcpt_tos == ["smtp@example.test"]
        assert b"/links/verify/" in envelope.content
    finally:
        controller.stop()


async def test_a_malformed_request_gets_the_stable_error_body(client, mail):
    res = await client.post("/api/account/signin", json={"email": "a@example.test"}, headers=H)
    assert (res.status_code, res.json()) == (422, {"error": "invalid_request"})
    bad_key = {"email": "a@example.test", "auth_key": "short", "device": device()}
    assert (await client.post("/api/account/signin", json=bad_key, headers=H)).json() == {"error": "invalid_request"}
