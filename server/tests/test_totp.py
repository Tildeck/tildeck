"""Two-factor sign-in for user accounts (docs/security-model.md, "Two-factor
sign-in"), against a real PostgreSQL."""

import asyncio
import secrets
import time

import pyotp
from sqlalchemy import text

from app import admins
from app.db import engine
from tests.test_accounts import H, Keys, b64, bearer, clean, device, mail, register  # noqa: F401 - fixtures


def fullwidth(code: str) -> str:
    """The same digits as fullwidth characters (U+FF10 to U+FF19)."""
    return "".join(chr(0xFF10 + int(d)) for d in code)


def arabic_indic(code: str) -> str:
    """The same digits as Arabic-Indic characters (U+0660 to U+0669)."""
    return "".join(chr(0x0660 + int(d)) for d in code)


class Phone:
    """The user's authenticator app, with a clock the server shares."""

    def __init__(self, secret: str, monkeypatch):
        self.totp = pyotp.TOTP(secret)
        self.now = time.time()
        monkeypatch.setattr(admins, "_now", lambda: self.now)

    def code(self) -> str:
        return self.totp.at(self.now)

    def next(self) -> str:
        """A code from a later step. A step whose code equals the previous
        step's is skipped: the server matches the earliest step in its
        window, which was already used."""
        self.now += self.totp.interval
        while self.code() == self.totp.at(self.now - self.totp.interval):
            self.now += self.totp.interval
        return self.code()

    def wrong(self) -> str:
        return wrong_code(self.totp, self.now)


def wrong_code(totp: pyotp.TOTP, now: float) -> str:
    """A random code the server refuses at [now]: no step in its window has it."""
    while True:
        code = f"{secrets.randbelow(999_999) + 1:06d}"
        if not totp.verify(code, for_time=now, valid_window=admins.TOTP_WINDOW):
            return code


def distinct_codes(now: float) -> pyotp.TOTP:
    """A new random secret whose codes differ in the five steps around [now],
    so a code names exactly one step."""
    while True:
        totp = pyotp.TOTP(pyotp.random_base32())
        if len({totp.at(now + k * totp.interval) for k in range(-2, 3)}) == 5:
            return totp


def test_a_code_from_one_step_either_way_is_accepted_and_names_its_step():
    now = time.time()
    totp = distinct_codes(now)
    step = int(now) // totp.interval

    def code(k: int) -> str:
        return totp.at(now + k * totp.interval)

    for k in (-1, 0, 1):
        assert admins.totp_step(totp.secret, code(k), None, now) == step + k
    for k in (-2, 2):
        assert admins.totp_step(totp.secret, code(k), None, now) is None
    # The last accepted step and earlier ones are used; a later one is not.
    assert admins.totp_step(totp.secret, code(0), step, now) is None
    assert admins.totp_step(totp.secret, code(-1), step, now) is None
    assert admins.totp_step(totp.secret, code(1), step, now) == step + 1
    # Spaces around and inside the code are ignored, as before.
    assert admins.totp_step(totp.secret, f" {code(0)[:3]} {code(0)[3:]} ", None, now) == step
    assert admins.totp_step(totp.secret, "", None, now) is None
    assert admins.totp_step(totp.secret, code(0) + "0", None, now) is None


def test_digits_other_than_ascii_are_refused_like_a_wrong_code():
    now = time.time()
    totp = pyotp.TOTP(pyotp.random_base32())
    for typed in (fullwidth(totp.at(now)), arabic_indic(totp.at(now))):
        assert admins.totp_step(totp.secret, typed, None, now) is None


async def turn_on(client, token: str, monkeypatch) -> Phone:
    start = await client.post("/api/account/totp/start", headers=bearer(token))
    assert start.status_code == 200, start.status_code
    enrollment = start.json()
    assert enrollment["uri"].startswith("otpauth://totp/Tildeck:")
    assert enrollment["qr_image"].startswith("data:image/svg+xml")
    phone = Phone(enrollment["secret"], monkeypatch)
    done = await client.post("/api/account/totp/confirm", json={"code": phone.code()}, headers=bearer(token))
    assert done.status_code == 204, done.status_code
    return phone


async def test_turning_it_on_needs_a_code_from_the_new_secret(client, mail, monkeypatch):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    assert (await client.get("/api/account", headers=bearer(token))).json()["totp_enabled"] is False

    start = (await client.post("/api/account/totp/start", headers=bearer(token))).json()
    phone = Phone(start["secret"], monkeypatch)
    wrong = await client.post("/api/account/totp/confirm", json={"code": phone.wrong()}, headers=bearer(token))
    assert (wrong.status_code, wrong.json()) == (401, {"error": "invalid_totp"})
    assert (await client.get("/api/account", headers=bearer(token))).json()["totp_enabled"] is False

    other = await client.post(
        "/api/account/totp/confirm", json={"code": fullwidth(phone.code())}, headers=bearer(token)
    )
    assert (other.status_code, other.json()) == (401, {"error": "invalid_totp"})
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
    res = await signin(totp_code=phone.wrong())
    assert (res.status_code, res.json()) == (401, {"error": "invalid_credentials"})

    code = phone.next()
    assert (await signin(totp_code=code)).status_code == 202, "both factors: on to approval"
    replay = await signin(totp_code=code)
    assert (replay.status_code, replay.json()) == (401, {"error": "invalid_credentials"}), "a code works once"
    # Signing in with the code does not use up the limit.
    for _ in range(12):
        assert (await signin(totp_code=phone.next())).status_code == 202


async def _waiting_behind(holder_pid: int, count: int) -> bool:
    """True once [count] database sessions wait, directly or behind another
    waiter, on the lock [holder_pid] holds. Each sample uses its own
    transaction, so it sees the current activity."""
    for _ in range(200):
        async with engine.connect() as conn:
            rows = (
                await conn.execute(
                    text(
                        "SELECT pid, pg_blocking_pids(pid) FROM pg_stat_activity "
                        "WHERE datname = current_database() AND pid <> pg_backend_pid()"
                    )
                )
            ).all()
        blocked_by = {pid: set(blockers) for pid, blockers in rows if blockers}

        def reaches(pid: int, seen: frozenset = frozenset()) -> bool:
            blockers = blocked_by.get(pid, set())
            return holder_pid in blockers or any(b not in seen and reaches(b, seen | {pid}) for b in blockers)

        if sum(1 for pid in blocked_by if pid != holder_pid and reaches(pid)) >= count:
            return True
        await asyncio.sleep(0.05)
    return False


async def test_a_code_sent_twice_at_once_signs_in_once(client, mail, monkeypatch):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    phone = await turn_on(client, token, monkeypatch)
    code = phone.next()
    body = {"email": keys.email, "auth_key": keys.auth_key, "device": keys.device, "totp_code": code}

    # The test holds the account's row lock until both sign-ins wait on it,
    # so both are in flight at the same time when they check the code.
    holder = await engine.connect()
    try:
        await holder.begin()
        await holder.execute(text("SELECT id FROM accounts WHERE email = :e FOR UPDATE"), {"e": keys.email})
        holder_pid = await holder.scalar(text("SELECT pg_backend_pid()"))
        # The task group waits for both sign-ins, or cancels them, before
        # the test goes on, whatever fails.
        async with asyncio.TaskGroup() as group:
            attempts = [group.create_task(client.post("/api/account/signin", json=body, headers=H)) for _ in range(2)]
            try:
                both_waited = await _waiting_behind(holder_pid, 2)
            finally:
                await holder.rollback()
        answers = [attempt.result() for attempt in attempts]
    finally:
        await holder.close()

    assert both_waited, "both sign-ins reached the row lock"
    assert sorted((a.status_code, a.json().get("error")) for a in answers) == [
        (202, None),
        (401, "invalid_credentials"),
    ]
    async with engine.begin() as conn:
        stored = await conn.scalar(text("SELECT totp_last_step FROM accounts WHERE email = :e"), {"e": keys.email})
    assert stored == int(phone.now) // phone.totp.interval


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
    assert res.status_code == 204, res.status_code


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
    assert res.status_code == 200, res.status_code
    # The code was spent.
    res = await client.post(
        "/api/account/recovery/complete", json={**complete, "device": device(), "totp_code": code}, headers=H
    )
    assert (res.status_code, res.json()) == (401, {"error": "recovery_failed"})


async def test_turning_it_off_needs_a_current_code(client, mail, monkeypatch):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    phone = await turn_on(client, token, monkeypatch)
    res = await client.post("/api/account/totp/disable", json={"code": phone.wrong()}, headers=bearer(token))
    assert (res.status_code, res.json()) == (401, {"error": "invalid_totp"})
    res = await client.post("/api/account/totp/disable", json={"code": phone.next()}, headers=bearer(token))
    assert res.status_code == 204
    assert (await client.get("/api/account", headers=bearer(token))).json()["totp_enabled"] is False
    assert any("Two-factor sign-in is off" in m.subject for m in mail.sent)
    body = {"email": keys.email, "auth_key": keys.auth_key, "device": keys.device}
    assert (await client.post("/api/account/signin", json=body, headers=H)).status_code == 202

    async with engine.begin() as conn:
        actions = (await conn.execute(text("SELECT action FROM audit_entries ORDER BY id"))).scalars().all()
    assert "totp_enabled" in actions and "totp_disabled" in actions
