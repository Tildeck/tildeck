"""Account and device changes sent at the same time, against a real
PostgreSQL. Each test holds a row lock from its own connection and sends the
racing requests one at a time, each once the ones before it wait on that
lock, so all are in flight together and queue in a known order. Then it lets
go and checks that every request got the answer it gets when it runs alone
after the ones before it, and what was stored."""

import asyncio
import secrets
from dataclasses import dataclass

import pyotp
from sqlalchemy import text

from app import accounts, admins, crypto
from app.db import engine
from tests.test_accounts import H, Keys, b64, bearer, device, mail, register, verify  # noqa: F401 - mail is a fixture
from tests.test_admin import clean, panel  # noqa: F401 - fixtures
from tests.test_totp import Phone, turn_on

LOCK_ACCOUNT = "SELECT id FROM accounts WHERE email = :e FOR UPDATE"
LOCK_DEVICE = "SELECT id FROM devices WHERE id = :d FOR UPDATE"


async def _waiters(holder_pid: int) -> dict[int, tuple[set[int], str]]:
    """The backends that wait, directly or behind another waiter, on a lock
    [holder_pid] holds, with what blocks each one and the statement it
    waits in."""
    async with engine.connect() as conn:
        rows = (
            await conn.execute(
                text(
                    "SELECT pid, pg_blocking_pids(pid), query FROM pg_stat_activity "
                    "WHERE datname = current_database() AND pid <> pg_backend_pid()"
                )
            )
        ).all()
    blocked_by = {pid: set(blockers) for pid, blockers, _ in rows if blockers}
    queries = {pid: query for pid, _, query in rows}

    def reaches(pid: int, seen: frozenset = frozenset()) -> bool:
        blockers = blocked_by.get(pid, set())
        return holder_pid in blockers or any(b not in seen and reaches(b, seen | {pid}) for b in blockers)

    return {pid: (blocked_by[pid], queries[pid]) for pid in blocked_by if pid != holder_pid and reaches(pid)}


@dataclass
class Race:
    answers: list
    # The statement each request waited in, in the order they were sent.
    waits: list[str]
    # Each request waited behind the one sent before it: they queued for
    # the same row, in that order.
    queued: bool

    def __str__(self) -> str:
        # For a failure message: status and error codes and the statements
        # waited in (their parameters are not part of the text), never a body.
        return f"answers {[answer(a) for a in self.answers]}, queued {self.queued}, waited in {self.waits}"


async def in_order(hold: str, params: dict, *requests) -> Race:
    """Runs [hold] in a transaction of its own, which keeps the rows it
    locks; sends [requests] in order, each once one more backend waits on
    that lock; then rolls the transaction back."""
    holder = await engine.connect()
    pids: list[int] = []
    try:
        await holder.begin()
        await holder.execute(text(hold), params)
        holder_pid = await holder.scalar(text("SELECT pg_backend_pid()"))
        # The task group waits for every request, or cancels them, before
        # the test goes on, whatever fails.
        async with asyncio.TaskGroup() as group:
            sent = []
            try:
                for request in requests:
                    sent.append(group.create_task(request()))
                    for _ in range(200):
                        now = await _waiters(holder_pid)
                        if len(now) > len(pids):
                            break
                        await asyncio.sleep(0.05)
                    new = [pid for pid in now if pid not in pids]
                    if len(new) != 1 or len(now) != len(sent):
                        last = sent[-1]
                        if not last.done():
                            done = "still running"
                        elif last.exception() is not None:
                            # The type only: a database error's text can
                            # carry the statement's parameters.
                            done = f"failed with {type(last.exception()).__name__}"
                        else:
                            done = f"finished with {last.result().status_code}"
                        raise AssertionError(f"request {len(sent)} did not wait on the lock ({done}): {now}")
                    pids += new
            finally:
                await holder.rollback()
        queued = all(pids[i - 1] in now[pids[i]][0] for i in range(1, len(pids)))
        return Race([task.result() for task in sent], [now[pid][1] for pid in pids], queued)
    finally:
        await holder.close()


def answer(res) -> tuple:
    return res.status_code, res.json().get("error") if res.content else None


async def stored(email: str, expression: str):
    async with engine.connect() as conn:
        return await conn.scalar(text(f"SELECT {expression} FROM accounts WHERE email = :e"), {"e": email})


async def entries(action: str) -> int:
    async with engine.connect() as conn:
        return await conn.scalar(text("SELECT count(*) FROM audit_entries WHERE action = :a"), {"a": action})


def signin(client, keys: Keys, phone_device: dict | None = None, **extra):
    body = {"email": keys.email, "auth_key": keys.auth_key, "device": phone_device or device("Phone"), **extra}
    return lambda: client.post("/api/account/signin", json=body, headers=H)


def confirm(client, token: str, code: str):
    return lambda: client.post("/api/account/totp/confirm", json={"code": code}, headers=bearer(token))


async def enrolling(client, token: str, monkeypatch) -> str:
    """Starts turning two-factor sign-in on; a code from the new secret."""
    start = (await client.post("/api/account/totp/start", headers=bearer(token))).json()
    return Phone(start["secret"], monkeypatch).code()


async def administrator(panel) -> dict:  # noqa: F811
    """A first administrator with a password and TOTP secret made for this
    run; the CSRF header of its session."""
    token = admins.setup.issue()
    body = {"setup_token": token, "username": "operator", "password": secrets.token_urlsafe(24)}
    start = await panel.post("/api/admin/setup/start", json=body)
    assert start.status_code == 200, start.status_code
    code = pyotp.TOTP(start.json()["secret"]).now()
    done = await panel.post("/api/admin/setup/complete", json={"setup_token": token, "code": code})
    assert done.status_code == 200, done.status_code
    return {"X-CSRF-Token": done.json()["csrf_token"]}


async def test_a_claim_token_sent_twice_at_once_collects_one_device_token(client, mail):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    phone = device("Phone")
    pending = await signin(client, keys, phone)()
    assert (await client.post(f"/api/devices/{phone['id']}/approve", headers=bearer(token))).status_code == 204
    claim = {"device_id": phone["id"], "claim_token": pending.json()["claim_token"]}

    race = await in_order(
        LOCK_DEVICE, {"d": phone["id"]}, *[lambda: client.post("/api/devices/claim", json=claim, headers=H)] * 2
    )

    assert [answer(a) for a in race.answers] == [(200, None), (401, "invalid_token")], race
    assert race.queued, race
    collected = race.answers[0].json()["device_token"]
    assert (await client.get("/api/account", headers=bearer(collected))).status_code == 200


async def test_a_code_confirmed_twice_at_once_turns_it_on_once(client, mail, monkeypatch):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    code = await enrolling(client, token, monkeypatch)

    race = await in_order(LOCK_ACCOUNT, {"e": keys.email}, confirm(client, token, code), confirm(client, token, code))

    assert [answer(a) for a in race.answers] == [(204, None), (409, "totp_not_enabled")], race
    assert race.queued, race
    assert await entries("totp_enabled") == 1
    assert sum("Two-factor sign-in is on" in m.subject for m in mail.sent) == 1


async def test_a_sign_in_that_waits_on_turning_it_on_needs_the_code(client, mail, monkeypatch):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    code = await enrolling(client, token, monkeypatch)

    race = await in_order(LOCK_ACCOUNT, {"e": keys.email}, confirm(client, token, code), signin(client, keys))

    assert [answer(a) for a in race.answers] == [(204, None), (401, "totp_required")], race
    assert race.queued, race


async def test_a_recovery_that_waits_on_turning_it_on_needs_the_code(client, mail, monkeypatch):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    code = await enrolling(client, token, monkeypatch)
    new = {"kdf": keys.kdf, "auth_key": b64(32), "wrap_pw": {"nonce": b64(24), "ct": b64(48)}}
    body = {"email": keys.email, "recovery_auth_key": keys.recovery_auth_key, "new": new, "device": device()}

    race = await in_order(
        LOCK_ACCOUNT,
        {"e": keys.email},
        confirm(client, token, code),
        lambda: client.post("/api/account/recovery/complete", json=body, headers=H),
    )

    assert [answer(a) for a in race.answers] == [(204, None), (401, "totp_required")], race
    assert race.queued, race
    assert await entries("recovery_used") == 0


async def test_a_sign_in_that_waits_on_turning_it_off_goes_on_without_it(client, mail, monkeypatch):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    phone = await turn_on(client, token, monkeypatch)
    off, then = phone.next(), phone.next()

    race = await in_order(
        LOCK_ACCOUNT,
        {"e": keys.email},
        lambda: client.post("/api/account/totp/disable", json={"code": off}, headers=bearer(token)),
        signin(client, keys, totp_code=then),
    )

    assert [answer(a) for a in race.answers] == [(204, None), (202, None)], race
    assert race.queued, race


async def test_a_new_secret_is_refused_once_a_waiting_confirm_turned_it_on(client, mail, monkeypatch):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    code = await enrolling(client, token, monkeypatch)

    race = await in_order(
        LOCK_ACCOUNT,
        {"e": keys.email},
        confirm(client, token, code),
        lambda: client.post("/api/account/totp/start", headers=bearer(token)),
    )

    assert [answer(a) for a in race.answers] == [(204, None), (409, "totp_already_enabled")], race
    assert race.queued, race
    assert await stored(keys.email, "totp_pending_encrypted IS NULL")


async def on_and_pending(client, keys: Keys, token: str, monkeypatch) -> tuple[Phone, str]:
    """A row an earlier version could leave behind: two-factor sign-in on,
    and another secret pending. The phone and the pending secret."""
    phone = await turn_on(client, token, monkeypatch)
    other = pyotp.random_base32()
    async with engine.begin() as conn:
        await conn.execute(
            text("UPDATE accounts SET totp_pending_encrypted = :p WHERE email = :e"),
            {"p": crypto.encrypt(other), "e": keys.email},
        )
    return phone, other


async def test_a_pending_secret_cannot_replace_the_one_in_use(client, mail, monkeypatch):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    phone, other = await on_and_pending(client, keys, token, monkeypatch)
    before = await stored(keys.email, "md5(totp_secret_encrypted)")

    res = await confirm(client, token, pyotp.TOTP(other).at(phone.now))()

    assert answer(res) == (409, "totp_already_enabled")
    assert await stored(keys.email, "md5(totp_secret_encrypted)") == before


async def test_turning_it_off_clears_a_pending_secret(client, mail, monkeypatch):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    phone, other = await on_and_pending(client, keys, token, monkeypatch)

    off = await client.post("/api/account/totp/disable", json={"code": phone.next()}, headers=bearer(token))
    assert off.status_code == 204
    res = await confirm(client, token, pyotp.TOTP(other).at(phone.now))()

    assert answer(res) == (409, "totp_not_enabled")
    assert await stored(keys.email, "totp_secret_encrypted IS NULL AND totp_pending_encrypted IS NULL")


async def test_a_sign_in_that_waits_on_deleting_the_account_is_refused(panel, client, mail, monkeypatch):  # noqa: F811
    csrf = await administrator(panel)
    keys = Keys("user@example.test")
    token = await register(client, keys)
    phone = await turn_on(client, token, monkeypatch)
    account_id = await stored(keys.email, "id")

    race = await in_order(
        LOCK_ACCOUNT,
        {"e": keys.email},
        lambda: panel.delete(f"/api/admin/users/{account_id}", headers=csrf),
        signin(client, keys, totp_code=phone.next()),
    )

    assert [answer(a) for a in race.answers] == [(204, None), (401, "invalid_credentials")], race
    assert race.queued, race


async def test_an_administrator_reset_that_waits_on_turning_it_on_turns_it_off(panel, client, mail, monkeypatch):  # noqa: F811
    csrf = await administrator(panel)
    keys = Keys("user@example.test")
    token = await register(client, keys)
    account_id = await stored(keys.email, "id")
    code = await enrolling(client, token, monkeypatch)

    race = await in_order(
        LOCK_ACCOUNT,
        {"e": keys.email},
        confirm(client, token, code),
        lambda: panel.post(f"/api/admin/users/{account_id}/totp/disable", headers=csrf),
    )

    assert [a.status_code for a in race.answers] == [204, 204], race
    assert race.queued, race
    assert await stored(keys.email, "totp_secret_encrypted IS NULL AND totp_pending_encrypted IS NULL")
    assert (await client.get("/api/account", headers=bearer(token))).json()["totp_enabled"] is False
    assert await entries("totp_reset") == 1
    assert sum("An administrator turned off two-factor sign-in" in m.subject for m in mail.sent) == 1


async def test_a_sign_in_that_waits_on_disabling_the_account_is_refused(panel, client, mail):  # noqa: F811
    csrf = await administrator(panel)
    keys = Keys("user@example.test")
    await register(client, keys)
    account_id = await stored(keys.email, "id")

    race = await in_order(
        LOCK_ACCOUNT,
        {"e": keys.email},
        lambda: panel.post(f"/api/admin/users/{account_id}/disable", headers=csrf),
        signin(client, keys),
    )

    assert [answer(a) for a in race.answers] == [(204, None), (403, "account_disabled")], race
    assert race.queued, race


async def test_a_change_that_waits_on_disabling_the_account_is_refused(panel, client, mail):  # noqa: F811
    csrf = await administrator(panel)
    keys = Keys("user@example.test")
    token = await register(client, keys)
    account_id = await stored(keys.email, "id")

    race = await in_order(
        LOCK_ACCOUNT,
        {"e": keys.email},
        lambda: panel.post(f"/api/admin/users/{account_id}/disable", headers=csrf),
        lambda: client.post("/api/account/totp/start", headers=bearer(token)),
    )

    assert [answer(a) for a in race.answers] == [(204, None), (403, "account_disabled")], race
    assert race.queued, race
    assert await stored(keys.email, "totp_pending_encrypted IS NULL")


async def test_an_account_disabled_twice_at_once_is_logged_once(panel, client, mail):  # noqa: F811
    csrf = await administrator(panel)
    keys = Keys("user@example.test")
    await register(client, keys)
    account_id = await stored(keys.email, "id")

    def disable():
        return panel.post(f"/api/admin/users/{account_id}/disable", headers=csrf)

    race = await in_order(LOCK_ACCOUNT, {"e": keys.email}, disable, disable)

    assert [a.status_code for a in race.answers] == [204, 204], race
    assert race.queued, race
    assert await entries("account_disabled") == 1


async def test_an_account_deleted_twice_at_once_is_deleted_once(panel, client, mail):  # noqa: F811
    csrf = await administrator(panel)
    keys = Keys("user@example.test")
    await register(client, keys)
    account_id = await stored(keys.email, "id")

    def delete():
        return panel.delete(f"/api/admin/users/{account_id}", headers=csrf)

    race = await in_order(LOCK_ACCOUNT, {"e": keys.email}, delete, delete)

    assert [answer(a) for a in race.answers] == [(204, None), (404, "not_found")], race
    assert race.queued, race
    assert await entries("account_deleted") == 1


async def test_two_password_changes_with_the_same_key_at_once_change_it_once(client, mail):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)

    def change():
        new = {"kdf": keys.kdf, "auth_key": b64(32), "wrap_pw": {"nonce": b64(24), "ct": b64(48)}}
        body = {"auth_key": keys.auth_key, "new": new, "keep_other_devices": True}
        return client.post("/api/account/password", json=body, headers=bearer(token))

    race = await in_order(LOCK_ACCOUNT, {"e": keys.email}, change, change)

    assert [answer(a) for a in race.answers] == [(204, None), (401, "invalid_credentials")], race
    assert race.queued, race
    assert await entries("password_changed") == 1


async def test_a_sign_in_that_waits_on_revoking_its_device_is_refused(client, mail):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    phone = device("Phone")
    pending = await signin(client, keys, phone)()
    assert (await client.post(f"/api/devices/{phone['id']}/approve", headers=bearer(token))).status_code == 204
    claim = {"device_id": phone["id"], "claim_token": pending.json()["claim_token"]}
    assert (await client.post("/api/devices/claim", json=claim, headers=H)).status_code == 200

    race = await in_order(
        LOCK_DEVICE,
        {"d": phone["id"]},
        lambda: client.post(f"/api/devices/{phone['id']}/revoke", headers=bearer(token)),
        signin(client, keys, phone),
    )

    assert [answer(a) for a in race.answers] == [(204, None), (409, "device_revoked")], race
    assert race.queued, race
    async with engine.connect() as conn:
        status = await conn.scalar(text("SELECT status FROM devices WHERE id = :d"), {"d": phone["id"]})
    assert status == "revoked"


async def test_an_account_enabled_twice_at_once_is_logged_once(panel, client, mail):  # noqa: F811
    csrf = await administrator(panel)
    keys = Keys("user@example.test")
    await register(client, keys)
    account_id = await stored(keys.email, "id")
    assert (await panel.post(f"/api/admin/users/{account_id}/disable", headers=csrf)).status_code == 204

    def enable():
        return panel.post(f"/api/admin/users/{account_id}/enable", headers=csrf)

    race = await in_order(LOCK_ACCOUNT, {"e": keys.email}, enable, enable)

    assert [a.status_code for a in race.answers] == [204, 204], race
    assert race.queued, race
    assert await entries("account_enabled") == 1


async def test_a_sign_in_with_the_old_key_that_waits_on_a_new_one_is_refused(client, mail):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    new = {"kdf": keys.kdf, "auth_key": b64(32), "wrap_pw": {"nonce": b64(24), "ct": b64(48)}}
    body = {"auth_key": keys.auth_key, "new": new, "keep_other_devices": True}

    race = await in_order(
        LOCK_ACCOUNT,
        {"e": keys.email},
        lambda: client.post("/api/account/password", json=body, headers=bearer(token)),
        signin(client, keys),
    )

    assert [answer(a) for a in race.answers] == [(204, None), (401, "invalid_credentials")], race
    assert race.queued, race


async def test_a_sign_in_that_waits_on_a_claim_of_its_device_asks_for_approval_again(client, mail):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    phone = device("Phone")
    pending = await signin(client, keys, phone)()
    assert (await client.post(f"/api/devices/{phone['id']}/approve", headers=bearer(token))).status_code == 204
    claim = {"device_id": phone["id"], "claim_token": pending.json()["claim_token"]}

    race = await in_order(
        LOCK_DEVICE,
        {"d": phone["id"]},
        lambda: client.post("/api/devices/claim", json=claim, headers=H),
        signin(client, keys, phone),
    )

    assert [answer(a) for a in race.answers] == [(200, None), (202, None)], race
    assert race.queued, race
    assert race.answers[1].json()["status"] == "pending"


async def test_a_change_from_a_device_that_waits_on_its_reapproval_is_refused(client, mail):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    await verify(client, mail, keys)
    phone = device("Phone")
    pending = await signin(client, keys, phone)()
    assert (await client.post(f"/api/devices/{phone['id']}/approve", headers=bearer(token))).status_code == 204
    claim = {"device_id": phone["id"], "claim_token": pending.json()["claim_token"]}
    phone_token = (await client.post("/api/devices/claim", json=claim, headers=H)).json()["device_token"]

    race = await in_order(
        LOCK_ACCOUNT,
        {"e": keys.email},
        # Its id with the key alone, while its token is live: it waits for approval again.
        signin(client, keys, phone),
        lambda: client.post("/api/account/totp/start", headers=bearer(phone_token)),
    )

    assert [answer(a) for a in race.answers] == [(202, None), (401, "unauthorized")], race
    assert race.queued, race
    assert await stored(keys.email, "totp_pending_encrypted IS NULL")


async def approved(client, keys: Keys, token: str, name: str = "Phone") -> tuple[dict, dict]:
    """Another device, approved from the first one but not yet collected:
    the device and its claim request."""
    phone = device(name)
    pending = await signin(client, keys, phone)()
    assert (await client.post(f"/api/devices/{phone['id']}/approve", headers=bearer(token))).status_code == 204
    return phone, {"device_id": phone["id"], "claim_token": pending.json()["claim_token"]}


async def collected(client, keys: Keys, token: str, name: str = "Phone") -> tuple[dict, str]:
    """Another device, approved and collected: the device and its token."""
    phone, claim = await approved(client, keys, token, name)
    res = await client.post("/api/devices/claim", json=claim, headers=H)
    assert res.status_code == 200, res.status_code
    return phone, res.json()["device_token"]


def recovery(client, keys: Keys, target: dict):
    new = {"kdf": keys.kdf, "auth_key": b64(32), "wrap_pw": {"nonce": b64(24), "ct": b64(48)}}
    body = {"email": keys.email, "recovery_auth_key": keys.recovery_auth_key, "new": new, "device": target}
    return lambda: client.post("/api/account/recovery/complete", json=body, headers=H)


async def device_column(device_id: str, expression: str):
    async with engine.connect() as conn:
        return await conn.scalar(text(f"SELECT {expression} FROM devices WHERE id = :d"), {"d": device_id})


async def test_a_change_with_a_token_that_recovery_replaced_is_refused(client, mail):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    phone, phone_token = await collected(client, keys, token)

    race = await in_order(
        LOCK_ACCOUNT,
        {"e": keys.email},
        recovery(client, keys, phone),
        lambda: client.post("/api/account/totp/start", headers=bearer(phone_token)),
    )

    assert [answer(a) for a in race.answers] == [(200, None), (401, "unauthorized")], race
    assert race.queued, race
    assert await device_column(phone["id"], "status") == "active"


async def test_an_administrator_reset_that_waits_on_deleting_the_account_finds_nothing(
    panel,  # noqa: F811
    client,
    mail,  # noqa: F811
    monkeypatch,
):
    csrf = await administrator(panel)
    keys = Keys("user@example.test")
    token = await register(client, keys)
    await turn_on(client, token, monkeypatch)
    account_id = await stored(keys.email, "id")

    race = await in_order(
        LOCK_ACCOUNT,
        {"e": keys.email},
        lambda: panel.delete(f"/api/admin/users/{account_id}", headers=csrf),
        lambda: panel.post(f"/api/admin/users/{account_id}/totp/disable", headers=csrf),
    )

    assert [answer(a) for a in race.answers] == [(204, None), (404, "not_found")], race
    assert race.queued, race
    assert await entries("totp_reset") == 0


async def test_a_claim_that_waits_on_recovery_onto_its_device_is_refused(client, mail):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    phone, claim = await approved(client, keys, token)

    race = await in_order(
        LOCK_DEVICE,
        {"d": phone["id"]},
        recovery(client, keys, phone),
        lambda: client.post("/api/devices/claim", json=claim, headers=H),
    )

    assert [answer(a) for a in race.answers] == [(200, None), (401, "invalid_token")], race
    assert race.queued, race
    recovered = race.answers[0].json()["device_token"]
    assert (await client.get("/api/account", headers=bearer(recovered))).status_code == 200


async def test_recovery_onto_a_revoked_device_drops_its_old_claim_token(client, mail):  # noqa: F811
    keys = Keys("user@example.test")
    token = await register(client, keys)
    phone, _ = await approved(client, keys, token)
    assert (await client.post(f"/api/devices/{phone['id']}/revoke", headers=bearer(token))).status_code == 204
    # A row an earlier version could leave behind: revoked, with a claim token.
    left = secrets.token_urlsafe(32)
    async with engine.begin() as conn:
        await conn.execute(
            text("UPDATE devices SET claim_token_hash = :h WHERE id = :d"),
            {"h": accounts.token_hash(left), "d": phone["id"]},
        )

    res = await recovery(client, keys, phone)()
    assert res.status_code == 200, res.status_code
    claim = await client.post("/api/devices/claim", json={"device_id": phone["id"], "claim_token": left}, headers=H)

    assert answer(claim) == (401, "invalid_token")
    assert (await client.get("/api/account", headers=bearer(res.json()["device_token"]))).status_code == 200


async def test_a_revoke_waits_for_a_change_its_device_has_started(panel, client, mail):  # noqa: F811
    csrf = await administrator(panel)
    keys = Keys("user@example.test")
    token = await register(client, keys)
    phone, phone_token = await collected(client, keys, token)
    third = device("Tablet")
    assert (await signin(client, keys, third)()).status_code == 202
    new = {"kdf": keys.kdf, "auth_key": b64(32), "wrap_pw": {"nonce": b64(24), "ct": b64(48)}}
    body = {"auth_key": keys.auth_key, "new": new, "keep_other_devices": False}

    # The change waits while it signs out the other devices, on the third one.
    race = await in_order(
        LOCK_DEVICE,
        {"d": third["id"]},
        lambda: client.post("/api/account/password", json=body, headers=bearer(phone_token)),
        lambda: panel.post(f"/api/admin/devices/{phone['id']}/revoke", headers=csrf),
    )

    assert [a.status_code for a in race.answers] == [204, 204], race
    assert race.queued, race
    assert await device_column(phone["id"], "status") == "revoked"
    # The change took effect: the new key signs in, the old one no longer does.
    assert (await signin(client, keys, auth_key=new["auth_key"])()).status_code == 202
    assert answer(await signin(client, keys)()) == (401, "invalid_credentials")


async def test_a_claim_that_waits_on_disabling_the_account_is_refused(panel, client, mail):  # noqa: F811
    csrf = await administrator(panel)
    keys = Keys("user@example.test")
    token = await register(client, keys)
    account_id = await stored(keys.email, "id")
    _, claim = await approved(client, keys, token)

    race = await in_order(
        LOCK_ACCOUNT,
        {"e": keys.email},
        lambda: panel.post(f"/api/admin/users/{account_id}/disable", headers=csrf),
        lambda: client.post("/api/devices/claim", json=claim, headers=H),
    )

    assert [answer(a) for a in race.answers] == [(204, None), (403, "account_disabled")], race
    assert race.queued, race
    # The refused claim did not use up the claim token: once the account is
    # back, the device still collects its approval with it.
    assert (await panel.post(f"/api/admin/users/{account_id}/enable", headers=csrf)).status_code == 204
    assert (await client.post("/api/devices/claim", json=claim, headers=H)).status_code == 200
