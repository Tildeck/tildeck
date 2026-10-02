"""The sync API against a real PostgreSQL: versions, revisions, conflicts,
tombstones, paging, and isolation between accounts."""

import uuid

import pytest
from sqlalchemy import text

from app.db import engine
from app.routers import account as account_routes
from app.routers import sync as sync_routes
from tests.test_accounts import Keys, b64, bearer, mail, register, verify  # noqa: F401 - mail is a fixture


@pytest.fixture(autouse=True)
async def clean():
    account_routes.limiter.reset()
    yield
    async with engine.begin() as conn:
        for table in ("records", "email_tokens", "devices", "accounts"):
            await conn.execute(text(f"DELETE FROM {table}"))


def live(record_id: str, version: int) -> dict:
    return {"id": record_id, "version": version, "deleted": False, "nonce": b64(24), "ct": b64(64)}


def tombstone(record_id: str, version: int) -> dict:
    return {"id": record_id, "version": version, "deleted": True}


async def signed_up(client, mail, email: str = "user@example.test") -> dict:  # noqa: F811
    keys = Keys(email)
    token = await register(client, keys)
    await verify(client, mail, keys)
    return bearer(token)


async def push(client, auth, *changes):
    res = await client.post("/api/sync/records", json={"changes": list(changes)}, headers=auth)
    assert res.status_code == 200, res.text
    return res.json()


async def pull(client, auth, since: int = 0):
    res = await client.get(f"/api/sync/records?since={since}", headers=auth)
    assert res.status_code == 200, res.text
    return res.json()


async def test_syncing_needs_a_confirmed_address(client, mail):  # noqa: F811
    token = await register(client, Keys("new@example.test"))
    res = await client.get("/api/sync/records", headers=bearer(token))
    assert (res.status_code, res.json()) == (403, {"error": "email_not_verified"})


async def test_records_come_back_in_revision_order_from_a_cursor(client, mail):  # noqa: F811
    auth = await signed_up(client, mail)
    a, b = str(uuid.uuid4()), str(uuid.uuid4())
    first = await push(client, auth, live(a, 1), live(b, 1))
    assert [x["revision"] for x in first["accepted"]] == [1, 2]
    assert first["conflicts"] == [] and first["revision"] == 2

    everything = await pull(client, auth)
    assert [r["id"] for r in everything["records"]] == [a, b]
    assert everything["revision"] == 2 and everything["more"] is False

    await push(client, auth, live(a, 2))
    since = await pull(client, auth, since=2)
    assert [(r["id"], r["version"], r["revision"]) for r in since["records"]] == [(a, 2, 3)]
    assert (await pull(client, auth, since=3)) == {"records": [], "revision": 3, "more": False}


async def test_only_the_next_version_is_accepted(client, mail):  # noqa: F811
    auth = await signed_up(client, mail)
    a = str(uuid.uuid4())
    await push(client, auth, live(a, 1))
    await push(client, auth, live(a, 2))

    stale = await push(client, auth, live(a, 2))
    assert stale["accepted"] == []
    [conflict] = stale["conflicts"]
    assert conflict["reason"] == "version_conflict" and conflict["current"]["version"] == 2

    skipped = await push(client, auth, live(str(uuid.uuid4()), 2))
    assert skipped["conflicts"][0]["current"] is None, "a new record starts at version 1"


async def test_deletions_are_tombstones_with_at_most_a_marker(client, mail):  # noqa: F811
    auth = await signed_up(client, mail)
    a, b = str(uuid.uuid4()), str(uuid.uuid4())
    await push(client, auth, live(a, 1))
    await push(client, auth, tombstone(a, 2))
    marker = {**tombstone(b, 1), "ct": b64(64), "nonce": b64(24)}
    await push(client, auth, marker)
    records = {r["id"]: r for r in (await pull(client, auth))["records"]}
    assert records[a]["deleted"] is True and records[a]["nonce"] is None and records[a]["ct"] is None
    # A deletion marker is kept as sent, for the other devices to check.
    assert records[b]["deleted"] is True and (records[b]["nonce"], records[b]["ct"]) == (marker["nonce"], marker["ct"])

    half = {**tombstone(str(uuid.uuid4()), 1), "ct": b64(64)}
    res = await client.post("/api/sync/records", json={"changes": [half]}, headers=auth)
    assert (res.status_code, res.json()) == (422, {"error": "invalid_request"})
    empty = {"id": str(uuid.uuid4()), "version": 1, "deleted": False}
    assert (await client.post("/api/sync/records", json={"changes": [empty]}, headers=auth)).status_code == 422


async def test_a_push_may_not_name_a_record_twice(client, mail):  # noqa: F811
    auth = await signed_up(client, mail)
    a = str(uuid.uuid4())
    res = await client.post("/api/sync/records", json={"changes": [live(a, 1), live(a, 2)]}, headers=auth)
    assert (res.status_code, res.json()) == (422, {"error": "invalid_request"})


async def test_accounts_never_see_each_other(client, mail):  # noqa: F811
    alice = await signed_up(client, mail, "alice@example.test")
    bob = await signed_up(client, mail, "bob@example.test")
    shared_id = str(uuid.uuid4())
    await push(client, alice, live(shared_id, 1))
    await push(client, alice, live(shared_id, 2))
    assert (await pull(client, bob))["records"] == []
    # The same record id in another account is a different record.
    assert (await push(client, bob, live(shared_id, 1)))["accepted"][0]["revision"] == 1


async def test_large_pulls_come_in_pages(client, mail, monkeypatch):  # noqa: F811
    monkeypatch.setattr(sync_routes, "PULL_LIMIT", 2)
    auth = await signed_up(client, mail)
    await push(client, auth, *[live(str(uuid.uuid4()), 1) for _ in range(5)])
    seen, cursor, more = [], 0, True
    while more:
        page = await pull(client, auth, since=cursor)
        seen += page["records"]
        cursor, more = page["revision"], page["more"]
    assert [r["revision"] for r in seen] == [1, 2, 3, 4, 5]


async def test_a_revoked_device_cannot_sync(client, mail):  # noqa: F811
    auth = await signed_up(client, mail)
    me = (await client.get("/api/account", headers=auth)).json()
    await client.post(f"/api/devices/{me['devices'][0]['id']}/revoke", headers=auth)
    assert (await client.get("/api/sync/records", headers=auth)).status_code == 401
