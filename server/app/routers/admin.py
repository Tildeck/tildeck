"""The admin panel's API (docs/security-model.md, "The admin panel").

Only the panel, served by this same server, calls it, so it stays out of the
client contract (server/openapi.json). Administrators see account metadata
only: no route returns ciphertext, wrapped keys, or hashes.
"""

import hmac
from datetime import datetime

from fastapi import APIRouter, Cookie, Depends, Header, Query, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app import accounts, admins, audit, clock, settings_store
from app.accounts import RateLimiter
from app.db import get_db
from app.models import Account, Admin, AdminSession, AuditEntry, Device, Record
from app.protocol import ApiError, ErrorCode
from app.routers.account import revoke_device

router = APIRouter(prefix="/api/admin", tags=["admin"], include_in_schema=False)

# Setup and sign-in attempts per client address, and failed sign-ins per
# administrator, in the limiter's 15-minute window.
ADDRESS_LIMIT = 30
USERNAME_LIMIT = 10
limiter = RateLimiter()

USERNAME_PATTERN = r"^[A-Za-z0-9._@-]{3,100}$"
MIN_PASSWORD = 12


def _address(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def _limit_address(request: Request) -> None:
    key = f"addr:{_address(request)}"
    if limiter.exceeded(key, ADDRESS_LIMIT):
        raise ApiError(429, ErrorCode.rate_limited)
    limiter.hit(key)


def _set_cookie(response: Response, token: str) -> None:
    # A session cookie: gone with the browser; the server also ends it after
    # 30 idle minutes or 12 hours.
    response.set_cookie(
        admins.SESSION_COOKIE,
        token,
        httponly=True,
        secure=True,
        samesite="strict",
        path="/api/admin",
    )


class SessionView(BaseModel):
    username: str
    csrf_token: str


class Caller:
    def __init__(self, admin: Admin, row: AdminSession) -> None:
        self.admin = admin
        self.session = row

    @property
    def name(self) -> str:
        return self.admin.username


async def current_admin(
    request: Request,
    tildeck_admin: str | None = Cookie(default=None),
    x_csrf_token: str | None = Header(default=None),
    session: AsyncSession = Depends(get_db),
) -> Caller:
    """The signed-in administrator. Every request that changes something also
    carries the session's CSRF token."""
    found = await admins.session_of(session, tildeck_admin)
    if found is None:
        raise ApiError(401, ErrorCode.unauthorized)
    row, admin = found
    if request.method not in ("GET", "HEAD") and not (
        x_csrf_token and hmac.compare_digest(x_csrf_token, row.csrf_token)
    ):
        raise ApiError(403, ErrorCode.csrf_failed)
    await session.commit()
    return Caller(admin, row)


# --- First-run setup ---------------------------------------------------------


class SetupState(BaseModel):
    needed: bool


class SetupStart(BaseModel):
    setup_token: str = Field(max_length=200)
    username: str = Field(pattern=USERNAME_PATTERN)
    password: str = Field(min_length=MIN_PASSWORD, max_length=1000)


class TotpEnrollment(BaseModel):
    secret: str
    uri: str
    qr_image: str


class SetupComplete(BaseModel):
    setup_token: str = Field(max_length=200)
    code: str = Field(max_length=20)


async def _setup_open(session: AsyncSession, request: Request, token: str) -> None:
    _limit_address(request)
    if await admins.admin_count(session) > 0:
        raise ApiError(409, ErrorCode.setup_not_needed)
    if not admins.setup.matches(token):
        raise ApiError(403, ErrorCode.invalid_setup_token)


@router.get("/setup", response_model=SetupState)
async def setup_state(session: AsyncSession = Depends(get_db)) -> SetupState:
    """Whether the server still waits for its first administrator."""
    return SetupState(needed=await admins.admin_count(session) == 0)


@router.post("/setup/start", response_model=TotpEnrollment)
async def setup_start(body: SetupStart, request: Request, session: AsyncSession = Depends(get_db)) -> TotpEnrollment:
    """Checks the setup token and returns a new TOTP secret to enroll. Nothing
    is stored until a code from it is confirmed."""
    await _setup_open(session, request, body.setup_token)
    password_hash = await accounts.hash_key(body.password)
    secret = admins.setup.begin(body.username, password_hash)
    uri = admins.otpauth_uri(secret, body.username)
    return TotpEnrollment(secret=secret, uri=uri, qr_image=admins.qr_image(uri))


@router.post("/setup/complete", response_model=SessionView)
async def setup_complete(
    body: SetupComplete, request: Request, response: Response, session: AsyncSession = Depends(get_db)
) -> SessionView:
    """Creates the first administrator once a code from the new TOTP secret
    is confirmed, and signs them in. An administrator never exists without a
    working second factor."""
    await _setup_open(session, request, body.setup_token)
    pending = admins.setup.pending()
    if pending is None:
        raise ApiError(403, ErrorCode.invalid_setup_token)
    step = admins.totp_step(pending.secret, body.code, None)
    if step is None:
        raise ApiError(401, ErrorCode.invalid_totp)
    admin = admins.new_admin(pending.username, pending.password_hash, pending.secret, step)
    session.add(admin)
    audit.record(
        session, actor=admin.username, source="admin", action="admin_created", entity="admin", entity_id=admin.id
    )
    token, csrf = await admins.open_session(session, admin)
    await session.commit()
    admins.setup.close()
    _set_cookie(response, token)
    return SessionView(username=admin.username, csrf_token=csrf)


# --- Sessions ----------------------------------------------------------------


class SignIn(BaseModel):
    username: str = Field(max_length=100)
    password: str = Field(max_length=1000)
    code: str = Field(max_length=20)


@router.post("/session", response_model=SessionView)
async def sign_in(
    body: SignIn, request: Request, response: Response, session: AsyncSession = Depends(get_db)
) -> SessionView:
    """Password and TOTP code. Failures look the same whichever part was
    wrong, and are logged."""
    _limit_address(request)
    user_key = f"admin:{body.username.lower()}"
    if limiter.exceeded(user_key, USERNAME_LIMIT):
        raise ApiError(429, ErrorCode.rate_limited)
    admin = await session.scalar(select(Admin).where(Admin.username == body.username))
    ok = (
        admin is not None
        and admin.disabled_at is None
        and await accounts.verify_key(admin.password_hash, body.password)
    )
    step = admins.totp_step(admins.secret_of(admin), body.code, admin.totp_last_step) if ok and admin else None
    if admin is None or step is None:
        limiter.hit(user_key)
        audit.record(
            session,
            actor=body.username[:100],
            source="admin",
            action="admin_signin_failed",
            entity="admin",
            entity_id=admin.id if admin else None,
        )
        await session.commit()
        raise ApiError(401, ErrorCode.invalid_credentials)
    admin.totp_last_step = step
    token, csrf = await admins.open_session(session, admin)
    audit.record(
        session, actor=admin.username, source="admin", action="admin_signin", entity="admin", entity_id=admin.id
    )
    await session.commit()
    _set_cookie(response, token)
    return SessionView(username=admin.username, csrf_token=csrf)


@router.get("/session", response_model=SessionView)
async def get_session(caller: Caller = Depends(current_admin)) -> SessionView:
    return SessionView(username=caller.name, csrf_token=caller.session.csrf_token)


@router.delete("/session", status_code=204)
async def sign_out(
    tildeck_admin: str | None = Cookie(default=None),
    caller: Caller = Depends(current_admin),
    session: AsyncSession = Depends(get_db),
) -> Response:
    await admins.close_session(session, tildeck_admin)
    await session.commit()
    response = Response(status_code=204)
    response.delete_cookie(admins.SESSION_COOKIE, path="/api/admin", secure=True, httponly=True, samesite="strict")
    return response


# --- Users and devices -------------------------------------------------------


class DeviceRow(BaseModel):
    id: str
    name: str
    status: str
    created_at: datetime
    last_seen_at: datetime | None


class UserRow(BaseModel):
    id: str
    email: str
    email_verified: bool
    disabled: bool
    created_at: datetime
    last_seen_at: datetime | None
    devices: int
    records: int
    storage_bytes: int


class UserDetail(UserRow):
    locale: str
    device_list: list[DeviceRow]


async def _user_rows(session: AsyncSession, account_id: str | None = None) -> list[UserRow]:
    devices = (
        select(
            Device.account_id,
            func.count().filter(Device.status != "revoked").label("devices"),
            func.max(Device.last_seen_at).label("last_seen"),
        )
        .group_by(Device.account_id)
        .subquery()
    )
    records = (
        select(
            Record.account_id,
            func.count().filter(Record.deleted.is_(False)).label("records"),
            func.coalesce(func.sum(func.length(Record.ct)), 0).label("storage"),
        )
        .group_by(Record.account_id)
        .subquery()
    )
    query = (
        select(Account, devices.c.devices, devices.c.last_seen, records.c.records, records.c.storage)
        .outerjoin(devices, devices.c.account_id == Account.id)
        .outerjoin(records, records.c.account_id == Account.id)
        .order_by(Account.created_at.desc())
    )
    if account_id is not None:
        query = query.where(Account.id == account_id)
    return [
        UserRow(
            id=account.id,
            email=account.email,
            email_verified=account.email_verified_at is not None,
            disabled=account.disabled_at is not None,
            created_at=account.created_at,
            last_seen_at=last_seen,
            devices=device_count or 0,
            records=record_count or 0,
            storage_bytes=int(storage or 0),
        )
        for account, device_count, last_seen, record_count, storage in (await session.execute(query)).all()
    ]


async def _account(session: AsyncSession, account_id: str) -> Account:
    account = await session.get(Account, account_id)
    if account is None:
        raise ApiError(404, ErrorCode.not_found)
    return account


@router.get("/users", response_model=list[UserRow])
async def list_users(caller: Caller = Depends(current_admin), session: AsyncSession = Depends(get_db)) -> list[UserRow]:
    return await _user_rows(session)


@router.get("/users/{account_id}", response_model=UserDetail)
async def get_user(
    account_id: str, caller: Caller = Depends(current_admin), session: AsyncSession = Depends(get_db)
) -> UserDetail:
    account = await _account(session, account_id)
    [row] = await _user_rows(session, account.id)
    device_list = (
        await session.scalars(select(Device).where(Device.account_id == account.id).order_by(Device.created_at))
    ).all()
    return UserDetail(
        **row.model_dump(),
        locale=account.locale,
        device_list=[
            DeviceRow(id=d.id, name=d.name, status=d.status, created_at=d.created_at, last_seen_at=d.last_seen_at)
            for d in device_list
        ],
    )


async def _set_disabled(session: AsyncSession, caller: Caller, account_id: str, disabled: bool) -> Response:
    account = await _account(session, account_id)
    if (account.disabled_at is not None) != disabled:
        account.disabled_at = clock.now() if disabled else None
        audit.record(
            session,
            actor=caller.name,
            source="admin",
            action="account_disabled" if disabled else "account_enabled",
            entity="account",
            entity_id=account.id,
            new_value=account.email,
        )
        await session.commit()
    return Response(status_code=204)


@router.post("/users/{account_id}/disable", status_code=204)
async def disable_user(
    account_id: str, caller: Caller = Depends(current_admin), session: AsyncSession = Depends(get_db)
) -> Response:
    """The account's devices stop syncing at once; nothing is deleted."""
    return await _set_disabled(session, caller, account_id, True)


@router.post("/users/{account_id}/enable", status_code=204)
async def enable_user(
    account_id: str, caller: Caller = Depends(current_admin), session: AsyncSession = Depends(get_db)
) -> Response:
    return await _set_disabled(session, caller, account_id, False)


@router.delete("/users/{account_id}", status_code=204)
async def delete_user(
    account_id: str, caller: Caller = Depends(current_admin), session: AsyncSession = Depends(get_db)
) -> Response:
    """Deletes the account with its devices and records. The vaults on the
    user's devices stay, locked with the master password."""
    account = await _account(session, account_id)
    audit.record(
        session,
        actor=caller.name,
        source="admin",
        action="account_deleted",
        entity="account",
        entity_id=account.id,
        old_value=account.email,
    )
    await session.execute(delete(Account).where(Account.id == account.id))
    await session.commit()
    return Response(status_code=204)


@router.post("/devices/{device_id}/revoke", status_code=204)
async def revoke(
    device_id: str, request: Request, caller: Caller = Depends(current_admin), session: AsyncSession = Depends(get_db)
) -> Response:
    device = await session.get(Device, device_id)
    if device is None:
        raise ApiError(404, ErrorCode.not_found)
    account = await _account(session, device.account_id)
    await revoke_device(request, session, account, device, actor=caller.name, source="admin")
    return Response(status_code=204)


# --- Settings ----------------------------------------------------------------


class SettingRow(BaseModel):
    key: str
    secret: bool
    kind: str
    choices: list[str] | None
    locked: bool
    origin: str
    configured: bool
    description: str
    value: str | None = None


class SettingChange(BaseModel):
    value: str = Field(max_length=2000)


@router.get("/settings", response_model=list[SettingRow])
async def list_settings(
    caller: Caller = Depends(current_admin), session: AsyncSession = Depends(get_db)
) -> list[SettingRow]:
    """Every setting and where its value comes from. Secret values never
    leave the server; the row says only whether one is set."""
    return [SettingRow(**row) for row in await settings_store.describe_all(session)]


@router.put("/settings/{key}", status_code=204)
async def change_setting(
    key: str, body: SettingChange, caller: Caller = Depends(current_admin), session: AsyncSession = Depends(get_db)
) -> Response:
    try:
        await settings_store.set_value(session, key, body.value, actor=caller.name, source="admin")
    except settings_store.UnknownSetting:
        raise ApiError(404, ErrorCode.not_found) from None
    except settings_store.SettingLocked:
        raise ApiError(409, ErrorCode.setting_locked) from None
    except settings_store.InvalidSettingValue:
        raise ApiError(422, ErrorCode.invalid_request) from None
    await session.commit()
    return Response(status_code=204)


# --- Activity log ------------------------------------------------------------


class ActivityRow(BaseModel):
    id: int
    at: datetime
    actor: str
    source: str
    action: str
    entity: str
    entity_id: str | None
    old_value: str | None
    new_value: str | None


class ActivityPage(BaseModel):
    entries: list[ActivityRow]
    more: bool


@router.get("/activity", response_model=ActivityPage)
async def activity(
    before: int | None = Query(default=None, ge=1),
    limit: int = Query(default=50, ge=1, le=200),
    caller: Caller = Depends(current_admin),
    session: AsyncSession = Depends(get_db),
) -> ActivityPage:
    """Newest first; page with the id of the last entry seen. Secret values
    were redacted when they were written."""
    query = select(AuditEntry).order_by(AuditEntry.id.desc()).limit(limit + 1)
    if before is not None:
        query = query.where(AuditEntry.id < before)
    rows = (await session.scalars(query)).all()
    return ActivityPage(
        entries=[
            ActivityRow(
                id=r.id,
                at=r.at,
                actor=r.actor,
                source=r.source,
                action=r.action,
                entity=r.entity,
                entity_id=r.entity_id,
                old_value=r.old_value,
                new_value=r.new_value,
            )
            for r in rows[:limit]
        ],
        more=len(rows) > limit,
    )
