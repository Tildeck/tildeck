"""The admin panel's API (docs/security-model.md, "The admin panel").

Only the panel, served by this same server, calls it, so it stays out of the
client contract (server/openapi.json). Administrators see account metadata
only: no route returns ciphertext, wrapped keys, or hashes.
"""

import hmac
import secrets
from datetime import datetime, timedelta

from fastapi import APIRouter, Cookie, Depends, Header, Query, Request, Response
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app import accounts, admins, audit, clock, settings_store
from app.accounts import RateLimiter
from app.db import get_db
from app.models import Account, Admin, AdminSession, AuditEntry, Device, Invite, Record
from app.protocol import ApiError, ErrorCode
from app.routers.account import mail_account, revoke_device, send_invite

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
    if not limiter.take(f"addr:{_address(request)}", ADDRESS_LIMIT):
        raise ApiError(429, ErrorCode.rate_limited)


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
    # Counted as a failure from the start, as for accounts: concurrent
    # attempts cannot all pass while the password is being checked.
    user_key = f"admin:{body.username.lower()}"
    if not limiter.take(user_key, USERNAME_LIMIT):
        raise ApiError(429, ErrorCode.rate_limited)
    # Locked until this attempt commits: two sign-ins with the same code
    # cannot both read the old last step and both pass.
    admin = await session.scalar(select(Admin).where(Admin.username == body.username).with_for_update())
    usable = admin if admin is not None and admin.disabled_at is None else None
    # Verified even without a usable administrator, so the time taken does
    # not tell which usernames exist.
    ok = await accounts.verify_key(usable.password_hash if usable else None, body.password)
    step = admins.totp_step(admins.secret_of(admin), body.code, admin.totp_last_step) if ok and admin else None
    if admin is None or step is None:
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
    limiter.give_back(user_key)
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
    totp_enabled: bool
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
        totp_enabled=account.totp_secret_encrypted is not None,
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


@router.post("/users/{account_id}/totp/disable", status_code=204)
async def disable_user_totp(
    account_id: str, request: Request, caller: Caller = Depends(current_admin), session: AsyncSession = Depends(get_db)
) -> Response:
    """For a user who lost the authenticator: two-factor sign-in goes off,
    the activity log records who did it, and the user is told by email."""
    account = await _account(session, account_id)
    if account.totp_secret_encrypted is None and account.totp_pending_encrypted is None:
        return Response(status_code=204)
    account.totp_secret_encrypted = account.totp_pending_encrypted = account.totp_last_step = None
    audit.record(
        session,
        actor=caller.name,
        source="admin",
        action="totp_reset",
        entity="account",
        entity_id=account.id,
        new_value=account.email,
    )
    await session.commit()
    await mail_account(request, session, account, "totp_reset")
    return Response(status_code=204)


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


class SettingsChange(BaseModel):
    values: dict[str, str] = Field(max_length=50)


@router.get("/settings", response_model=list[SettingRow])
async def list_settings(
    caller: Caller = Depends(current_admin), session: AsyncSession = Depends(get_db)
) -> list[SettingRow]:
    """Every setting and where its value comes from. Secret values never
    leave the server; the row says only whether one is set."""
    return [SettingRow(**row) for row in await settings_store.describe_all(session)]


@router.put("/settings", status_code=204)
async def change_settings(
    body: SettingsChange, caller: Caller = Depends(current_admin), session: AsyncSession = Depends(get_db)
) -> Response:
    """Saves every changed setting of the page together: all of them or none.
    A refusal names the setting it is about, so the panel shows it under
    that field."""
    refusals = {
        settings_store.UnknownSetting: (404, ErrorCode.not_found),
        settings_store.SettingLocked: (409, ErrorCode.setting_locked),
        settings_store.InvalidSettingValue: (422, ErrorCode.invalid_request),
    }
    for key, value in body.values.items():
        try:
            if len(value) > 2000:
                raise settings_store.InvalidSettingValue(key)
            await settings_store.set_value(session, key, value, actor=caller.name, source="admin")
        except tuple(refusals) as e:
            await session.rollback()
            status, code = refusals[type(e)]
            return JSONResponse({"error": code.value, "key": key}, status_code=status)
    await session.commit()
    return Response(status_code=204)


# --- Invitations -------------------------------------------------------------

INVITE_TTL = timedelta(days=7)


class InviteCreate(BaseModel):
    email: str = Field(max_length=320)
    locale: str = Field(default="en", pattern="^(en|he)$")


class InviteCreated(BaseModel):
    id: str
    email: str
    code: str
    expires_at: datetime
    emailed: bool


class InviteRow(BaseModel):
    id: str
    email: str
    created_by: str
    created_at: datetime
    expires_at: datetime
    status: str


def _invite_status(invite: Invite) -> str:
    if invite.used_at is not None:
        return "used"
    if invite.revoked_at is not None:
        return "revoked"
    if invite.expires_at <= clock.now():
        return "expired"
    return "open"


@router.post("/invites", response_model=InviteCreated, status_code=201)
async def create_invite(
    body: InviteCreate,
    request: Request,
    caller: Caller = Depends(current_admin),
    session: AsyncSession = Depends(get_db),
) -> InviteCreated:
    """An invitation for one address. The code is shown here once and, with
    email configured, sent to the address; the server keeps only its hash."""
    email = accounts.normalize_email(body.email)
    if not accounts.EMAIL_RE.match(email):
        raise ApiError(422, ErrorCode.invalid_email)
    if await session.scalar(select(Account).where(Account.email == email)) is not None:
        raise ApiError(409, ErrorCode.email_taken)
    code = secrets.token_urlsafe(12)
    invite = Invite(
        id=accounts.new_id(),
        code_hash=accounts.token_hash(code),
        email=email,
        created_by=caller.name,
        expires_at=clock.now() + INVITE_TTL,
    )
    session.add(invite)
    audit.record(
        session,
        actor=caller.name,
        source="admin",
        action="invite_created",
        entity="invite",
        entity_id=invite.id,
        new_value=email,
    )
    await session.commit()
    emailed = await send_invite(request, session, email, code, body.locale)
    return InviteCreated(id=invite.id, email=email, code=code, expires_at=invite.expires_at, emailed=emailed)


@router.get("/invites", response_model=list[InviteRow])
async def list_invites(
    caller: Caller = Depends(current_admin), session: AsyncSession = Depends(get_db)
) -> list[InviteRow]:
    rows = (await session.scalars(select(Invite).order_by(Invite.created_at.desc()))).all()
    return [
        InviteRow(
            id=i.id,
            email=i.email,
            created_by=i.created_by,
            created_at=i.created_at,
            expires_at=i.expires_at,
            status=_invite_status(i),
        )
        for i in rows
    ]


@router.post("/invites/{invite_id}/revoke", status_code=204)
async def revoke_invite(
    invite_id: str, caller: Caller = Depends(current_admin), session: AsyncSession = Depends(get_db)
) -> Response:
    invite = await session.get(Invite, invite_id)
    if invite is None:
        raise ApiError(404, ErrorCode.not_found)
    if invite.used_at is None and invite.revoked_at is None:
        invite.revoked_at = clock.now()
        audit.record(
            session,
            actor=caller.name,
            source="admin",
            action="invite_revoked",
            entity="invite",
            entity_id=invite.id,
            old_value=invite.email,
        )
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
