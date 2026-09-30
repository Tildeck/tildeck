"""The sync API (docs/security-model.md, "Sync").

Records are opaque: an id, a version the client sets, a tombstone flag, and
a nonce and ciphertext the server cannot read. The server enforces that a
change is exactly the next version of its record and stamps it with the
next revision of the account, which is the cursor clients pull from.
"""

from typing import Literal

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field, field_validator, model_validator
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app import accounts, clock
from app.db import get_db
from app.models import Account, Record
from app.protocol import ApiError, ErrorCode, errors, require_protocol
from app.routers.account import Caller, current_device

router = APIRouter(prefix="/api/sync", tags=["sync"], dependencies=[Depends(require_protocol)])

MAX_CHANGES = 500
MAX_CIPHERTEXT = 1024 * 1024  # base64 characters of one record
PULL_LIMIT = 1000

UUID_PATTERN = r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"


class SyncRecord(BaseModel):
    id: str = Field(pattern=UUID_PATTERN)
    version: int = Field(ge=1)
    deleted: bool
    nonce: str | None = None
    ct: str | None = Field(default=None, max_length=MAX_CIPHERTEXT)

    @field_validator("nonce")
    @classmethod
    def _nonce(cls, v: str | None) -> str | None:
        if v is not None:
            accounts._b64(v, length=24)
        return v

    @field_validator("ct")
    @classmethod
    def _ct(cls, v: str | None) -> str | None:
        if v is not None:
            accounts._b64(v, min_length=16)
        return v

    @model_validator(mode="after")
    def _content(self) -> "SyncRecord":
        # A tombstone carries no content; a live record always does.
        if self.deleted != (self.nonce is None and self.ct is None):
            raise ValueError("a record has content exactly when it is not deleted")
        return self


class StoredRecord(SyncRecord):
    revision: int


class PullResponse(BaseModel):
    records: list[StoredRecord]
    revision: int = Field(description="The cursor to pull from next time")
    more: bool = Field(description="More records are waiting beyond this page")


class PushRequest(BaseModel):
    changes: list[SyncRecord] = Field(max_length=MAX_CHANGES)


class Accepted(BaseModel):
    id: str
    version: int
    revision: int


class Conflict(BaseModel):
    """A change that was not the next version. current is what the server
    has (absent if the change claimed an existing record that does not exist)."""

    id: str
    reason: Literal["version_conflict"]
    current: StoredRecord | None


class PushResponse(BaseModel):
    accepted: list[Accepted]
    conflicts: list[Conflict]
    revision: int


def _stored(r: Record) -> StoredRecord:
    return StoredRecord(id=r.id, version=r.version, deleted=r.deleted, nonce=r.nonce, ct=r.ct, revision=r.revision)


def _verified(caller: Caller) -> None:
    if caller.account.email_verified_at is None:
        raise ApiError(403, ErrorCode.email_not_verified)


@router.get(
    "/records",
    response_model=PullResponse,
    operation_id="pullRecords",
    responses=errors((401, "Not signed in"), (403, "Email address not confirmed")),
)
async def pull(
    since: int = Query(default=0, ge=0),
    caller: Caller = Depends(current_device),
    session: AsyncSession = Depends(get_db),
) -> PullResponse:
    """Every record, tombstones included, stored after revision `since`, in
    revision order."""
    _verified(caller)
    rows = (
        await session.scalars(
            select(Record)
            .where(Record.account_id == caller.account.id, Record.revision > since)
            .order_by(Record.revision)
            .limit(PULL_LIMIT + 1)
        )
    ).all()
    more = len(rows) > PULL_LIMIT
    page = rows[:PULL_LIMIT]
    # With nothing new, the cursor moves to the account's latest revision.
    cursor = page[-1].revision if page else max(since, caller.account.revision)
    return PullResponse(records=[_stored(r) for r in page], revision=cursor, more=more)


@router.post(
    "/records",
    response_model=PushResponse,
    operation_id="pushRecords",
    responses=errors((401, "Not signed in"), (403, "Email address not confirmed"), (422, "Invalid request")),
)
async def push(
    body: PushRequest, caller: Caller = Depends(current_device), session: AsyncSession = Depends(get_db)
) -> PushResponse:
    """Stores each change that is exactly the next version of its record (1
    for a new record) and reports the others as conflicts with the current
    record. Revisions are assigned in one transaction per push, with the
    account row locked, so they never collide or go backwards."""
    _verified(caller)
    # populate_existing: the account is already in this session (loaded to
    # authenticate); the locked read must refresh its revision counter.
    account = await session.scalar(
        select(Account)
        .where(Account.id == caller.account.id)
        .with_for_update()
        .execution_options(populate_existing=True)
    )
    ids = [c.id for c in body.changes]
    # Each record at most once per push: the records are loaded once, below,
    # and a second change to a record created in this push would find it
    # missing and be stored as version 1 again.
    if len(set(ids)) != len(ids):
        raise ApiError(422, ErrorCode.invalid_request)
    existing = {
        r.id: r
        for r in (
            await session.scalars(select(Record).where(Record.account_id == account.id, Record.id.in_(ids)))
        ).all()
    }
    accepted, conflicts = [], []
    for change in body.changes:
        current = existing.get(change.id)
        expected = (current.version if current else 0) + 1
        if change.version != expected:
            conflicts.append(
                Conflict(id=change.id, reason="version_conflict", current=_stored(current) if current else None)
            )
            continue
        account.revision += 1
        if current is None:
            current = Record(account_id=account.id, id=change.id)
            session.add(current)
        current.version = change.version
        current.revision = account.revision
        current.deleted = change.deleted
        current.nonce = change.nonce
        current.ct = change.ct
        current.device_id = caller.device.id
        current.updated_at = clock.now()
        accepted.append(Accepted(id=change.id, version=change.version, revision=account.revision))
    await session.commit()
    return PushResponse(accepted=accepted, conflicts=conflicts, revision=account.revision)
