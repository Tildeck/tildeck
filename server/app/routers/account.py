"""The account and device API (docs/security-model.md, "Accounts and devices").

Every route here requires the Tildeck-Protocol header. Refusals carry a
stable error code. Nothing here accepts or returns a master password, a
vault key, or plaintext vault data.
"""

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, Header, Request, Response
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app import accounts, audit, clock, settings_store
from app.accounts import KdfParams, Sealed
from app.db import get_db
from app.mailer import Mail, email_configured, text
from app.models import Account, Device, EmailToken
from app.protocol import ApiError, ErrorCode, errors, require_protocol

logger = logging.getLogger("tildeck.accounts")

router = APIRouter(prefix="/api", tags=["account"], dependencies=[Depends(require_protocol)])

VERIFY_TTL = timedelta(hours=24)
APPROVE_TTL = timedelta(hours=1)


# --- Request and response bodies ---------------------------------------------


class DeviceInfo(BaseModel):
    id: str = Field(pattern=r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
    name: str = Field(min_length=1, max_length=100)


class NewPassword(BaseModel):
    kdf: KdfParams
    auth_key: str
    wrap_pw: Sealed

    _key = field_validator("auth_key")(accounts.key32)


class PreloginRequest(BaseModel):
    email: str = Field(max_length=320)


class PreloginResponse(BaseModel):
    kdf: KdfParams


class RegisterRequest(BaseModel):
    email: str = Field(max_length=320)
    locale: str = Field(default="en", pattern="^(en|he)$")
    vault_id: str = Field(pattern=r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
    kdf: KdfParams
    auth_key: str
    recovery_auth_key: str
    wrap_pw: Sealed
    wrap_rk: Sealed
    device: DeviceInfo

    _keys = field_validator("auth_key", "recovery_auth_key")(accounts.key32)


class VaultKeys(BaseModel):
    """What a device needs to open the vault with the master password."""

    vault_id: str
    kdf: KdfParams
    wrap_pw: Sealed


class SignedIn(BaseModel):
    """A device that may open the vault: its token and the wrapped key."""

    device_token: str
    email_verified: bool
    vault: VaultKeys


class SigninResult(BaseModel):
    """The answer to a sign-in: either the device is active (signed_in) or it
    waits for approval (pending). One shape, so clients switch on status."""

    status: Literal["active", "pending"]
    signed_in: SignedIn | None = None
    device_id: str | None = None
    claim_token: str | None = None
    email_approval: bool | None = Field(default=None, description="An approval link was sent by email")


class SigninRequest(BaseModel):
    email: str = Field(max_length=320)
    auth_key: str
    device: DeviceInfo

    _key = field_validator("auth_key")(accounts.key32)


class ClaimRequest(BaseModel):
    device_id: str
    claim_token: str = Field(max_length=100)


class DeviceView(BaseModel):
    id: str
    name: str
    status: Literal["pending", "active", "revoked"]
    created_at: datetime
    last_seen_at: datetime | None
    current: bool


class AccountView(BaseModel):
    email: str
    email_verified: bool
    locale: str
    devices: list[DeviceView]


class PasswordChange(BaseModel):
    auth_key: str
    new: NewPassword
    keep_other_devices: bool = False

    _key = field_validator("auth_key")(accounts.key32)


class RecoveryStart(BaseModel):
    email: str = Field(max_length=320)
    recovery_auth_key: str

    _key = field_validator("recovery_auth_key")(accounts.key32)


class RecoveryWrap(BaseModel):
    vault_id: str
    wrap_rk: Sealed


class RecoveryComplete(RecoveryStart):
    new: NewPassword
    device: DeviceInfo


# --- Helpers -----------------------------------------------------------------

limiter = accounts.RateLimiter()


def _address(request: Request) -> str:
    return request.client.host if request.client else "unknown"


async def _limit(session: AsyncSession, request: Request, email: str | None = None) -> None:
    """Refuse when the client address, or the account after failures, is over
    its limit. Checked before any expensive work."""
    per_address = int(await settings_store.get_value(session, "signin_limit_per_address") or 30)
    address_key = f"addr:{_address(request)}"
    if limiter.exceeded(address_key, per_address):
        raise ApiError(429, ErrorCode.rate_limited)
    limiter.hit(address_key)
    if email is not None:
        per_account = int(await settings_store.get_value(session, "signin_limit_per_account") or 10)
        if limiter.exceeded(f"acct:{email}", per_account):
            raise ApiError(429, ErrorCode.rate_limited)


def _failed(email: str) -> None:
    limiter.hit(f"acct:{email}")


def _vault_keys(account: Account) -> VaultKeys:
    return VaultKeys(
        vault_id=account.vault_id,
        kdf=KdfParams(alg="argon2id13", ops=account.kdf_ops, mem=account.kdf_mem, salt=account.kdf_salt),
        wrap_pw=Sealed.model_validate_json(account.wrap_pw),
    )


async def _server_label(session: AsyncSession) -> str:
    return await settings_store.get_value(session, "public_url") or "Tildeck"


async def _mail(request: Request, session: AsyncSession, account: Account, kind: str, **values: str) -> bool:
    """Sends a localized message; a failure is logged, never fatal: the
    action it reports has already happened."""
    if not await email_configured(session):
        return False
    values.setdefault("server", await _server_label(session))
    try:
        await request.app.state.mailer.send(
            session,
            Mail(
                to=account.email,
                subject=text(account.locale, f"{kind}_subject", **values),
                body=text(account.locale, f"{kind}_body", **values),
            ),
        )
        return True
    except Exception as exc:  # noqa: BLE001 - mail delivery must not undo the action
        logger.error("Could not send %s mail to account %s: %s", kind, account.id, exc)
        return False


async def _link(
    session: AsyncSession, account: Account, purpose: str, ttl: timedelta, device: Device | None = None
) -> str:
    token, token_hash = accounts.new_token()
    session.add(
        EmailToken(
            token_hash=token_hash,
            purpose=purpose,
            account_id=account.id,
            device_id=device.id if device else None,
            expires_at=accounts.expires_in(ttl),
        )
    )
    base = (await settings_store.get_value(session, "public_url") or "").rstrip("/")
    return f"{base}/links/{purpose}/{token}"


def _issue_token(device: Device) -> str:
    token, token_hash = accounts.new_token()
    device.token_hash = token_hash
    device.last_seen_at = clock.now()
    return token


async def _account_by_email(session: AsyncSession, email: str) -> Account | None:
    return await session.scalar(select(Account).where(Account.email == accounts.normalize_email(email)))


@dataclass
class Caller:
    """The authenticated device and its account, for a request."""

    account: Account
    device: Device


async def current_device(
    authorization: str | None = Header(default=None),
    session: AsyncSession = Depends(get_db),
) -> Caller:
    if not authorization or not authorization.startswith("Bearer "):
        raise ApiError(401, ErrorCode.unauthorized)
    device = await session.scalar(
        select(Device).where(Device.token_hash == accounts.token_hash(authorization.removeprefix("Bearer ").strip()))
    )
    if device is None or device.status != "active":
        raise ApiError(401, ErrorCode.unauthorized)
    account = await session.get(Account, device.account_id)
    if account is None or account.disabled_at is not None:
        raise ApiError(403, ErrorCode.account_disabled)
    idle_days = int(await settings_store.get_value(session, "device_idle_days") or 90)
    if device.last_seen_at and clock.now() - device.last_seen_at > timedelta(days=idle_days):
        device.token_hash = None
        await session.commit()
        raise ApiError(401, ErrorCode.token_expired)
    device.last_seen_at = clock.now()
    await session.commit()
    return Caller(account=account, device=device)


# --- Routes ------------------------------------------------------------------


@router.post(
    "/account/prelogin",
    response_model=PreloginResponse,
    operation_id="prelogin",
    responses=errors((429, "Too many requests")),
)
async def prelogin(
    body: PreloginRequest, request: Request, session: AsyncSession = Depends(get_db)
) -> PreloginResponse:
    """The KDF parameters for an address. An address without an account gets
    stable made-up parameters, so the answer does not reveal which exist."""
    await _limit(session, request)
    account = await _account_by_email(session, body.email)
    if account is None:
        return PreloginResponse(
            kdf=KdfParams(alg="argon2id13", **accounts.DEFAULT_KDF, salt=accounts.fake_salt(body.email))
        )
    return PreloginResponse(
        kdf=KdfParams(alg="argon2id13", ops=account.kdf_ops, mem=account.kdf_mem, salt=account.kdf_salt)
    )


@router.post(
    "/account/register",
    response_model=SignedIn,
    status_code=201,
    operation_id="register",
    responses=errors(
        (403, "Registration is not open"),
        (409, "The address has an account"),
        (422, "Invalid request"),
        (429, "Too many requests"),
    ),
)
async def register(body: RegisterRequest, request: Request, session: AsyncSession = Depends(get_db)) -> SignedIn:
    """Creates an account and signs in the registering device, which created
    the vault. Syncing waits until the email address is confirmed."""
    await _limit(session, request)
    email = accounts.normalize_email(body.email)
    if not accounts.EMAIL_RE.match(email):
        raise ApiError(422, ErrorCode.invalid_email)
    mode = await settings_store.get_value(session, "registration_mode")
    if mode == "closed":
        raise ApiError(403, ErrorCode.registration_closed)
    if mode == "invite":
        # Invitations are created in the admin panel (product step 6).
        raise ApiError(403, ErrorCode.registration_invite_required)
    if not await email_configured(session):
        raise ApiError(403, ErrorCode.registration_needs_email)
    if await _account_by_email(session, email) is not None:
        raise ApiError(409, ErrorCode.email_taken)
    if await session.get(Device, body.device.id) is not None:
        raise ApiError(409, ErrorCode.device_revoked)

    account = Account(
        id=accounts.new_id(),
        email=email,
        locale=body.locale,
        vault_id=body.vault_id,
        kdf_ops=body.kdf.ops,
        kdf_mem=body.kdf.mem,
        kdf_salt=body.kdf.salt,
        auth_key_hash=await accounts.hash_key(body.auth_key),
        recovery_auth_hash=await accounts.hash_key(body.recovery_auth_key),
        wrap_pw=body.wrap_pw.model_dump_json(),
        wrap_rk=body.wrap_rk.model_dump_json(),
    )
    session.add(account)
    device = Device(
        id=body.device.id, account_id=account.id, name=body.device.name, status="active", approved_at=clock.now()
    )
    session.add(device)
    token = _issue_token(device)
    link = await _link(session, account, "verify", VERIFY_TTL)
    audit.record(
        session, actor=email, source="user", action="account_registered", entity="account", entity_id=account.id
    )
    await session.commit()
    await _mail(request, session, account, "verify", link=link)
    await session.commit()
    return SignedIn(device_token=token, email_verified=False, vault=_vault_keys(account))


@router.post(
    "/account/signin",
    response_model=SigninResult,
    operation_id="signin",
    responses=errors(
        (401, "Wrong credentials"),
        (403, "Account disabled"),
        (409, "This device was revoked"),
        (429, "Too many requests"),
    ),
)
async def signin(
    body: SigninRequest, request: Request, response: Response, session: AsyncSession = Depends(get_db)
) -> SigninResult:
    """An active device receives its token and the wrapped vault key. A device
    the account does not know becomes pending and gets a one-time claim token;
    it receives nothing else until another device or an email link approves it."""
    email = accounts.normalize_email(body.email)
    await _limit(session, request, email)
    account = await _account_by_email(session, email)
    if account is None or not await accounts.verify_key(account.auth_key_hash, body.auth_key):
        _failed(email)
        audit.record(
            session,
            actor=email,
            source="user",
            action="signin_failed",
            entity="account",
            entity_id=account.id if account else None,
        )
        await session.commit()
        raise ApiError(401, ErrorCode.invalid_credentials)
    if account.disabled_at is not None:
        raise ApiError(403, ErrorCode.account_disabled)

    device = await session.get(Device, body.device.id)
    if device is not None and device.account_id != account.id:
        raise ApiError(409, ErrorCode.device_revoked)
    if device is not None and device.status == "revoked":
        raise ApiError(409, ErrorCode.device_revoked)
    if device is not None and device.status == "active":
        token = _issue_token(device)
        await session.commit()
        return SigninResult(
            status="active",
            signed_in=SignedIn(
                device_token=token, email_verified=account.email_verified_at is not None, vault=_vault_keys(account)
            ),
        )

    if device is None:
        device = Device(id=body.device.id, account_id=account.id, name=body.device.name, status="pending")
        session.add(device)
        audit.record(
            session,
            actor=email,
            source="user",
            action="device_pending",
            entity="device",
            entity_id=device.id,
            new_value=device.name,
        )
    claim, claim_hash = accounts.new_token()
    device.claim_token_hash = claim_hash
    emailed = False
    if account.email_verified_at is not None:
        link = await _link(session, account, "approve", APPROVE_TTL, device)
        await session.commit()
        emailed = await _mail(request, session, account, "approve", device=device.name, link=link)
    await session.commit()
    response.status_code = 202
    return SigninResult(status="pending", device_id=device.id, claim_token=claim, email_approval=emailed)


@router.post(
    "/devices/claim",
    response_model=SignedIn,
    operation_id="claimDevice",
    responses=errors((401, "Wrong claim token"), (409, "Not approved yet"), (429, "Too many requests")),
)
async def claim(body: ClaimRequest, request: Request, session: AsyncSession = Depends(get_db)) -> SignedIn:
    """The pending device collects its approval with the claim token only it
    has: its device token and the wrapped vault key."""
    # A waiting device asks every few seconds, so only wrong claim tokens
    # count against the address's limit.
    per_address = int(await settings_store.get_value(session, "signin_limit_per_address") or 30)
    address_key = f"addr:{_address(request)}"
    if limiter.exceeded(address_key, per_address):
        raise ApiError(429, ErrorCode.rate_limited)
    device = await session.get(Device, body.device_id)
    if (
        device is None
        or device.claim_token_hash is None
        or device.claim_token_hash != accounts.token_hash(body.claim_token)
    ):
        limiter.hit(address_key)
        raise ApiError(401, ErrorCode.invalid_token)
    if device.status == "pending":
        raise ApiError(409, ErrorCode.device_pending)
    if device.status != "active":
        raise ApiError(409, ErrorCode.device_revoked)
    account = await session.get(Account, device.account_id)
    device.claim_token_hash = None
    token = _issue_token(device)
    await session.commit()
    return SignedIn(
        device_token=token, email_verified=account.email_verified_at is not None, vault=_vault_keys(account)
    )


@router.get("/account", response_model=AccountView, operation_id="getAccount", responses=errors((401, "Not signed in")))
async def get_account(caller: Caller = Depends(current_device), session: AsyncSession = Depends(get_db)) -> AccountView:
    devices = (
        await session.scalars(select(Device).where(Device.account_id == caller.account.id).order_by(Device.created_at))
    ).all()
    return AccountView(
        email=caller.account.email,
        email_verified=caller.account.email_verified_at is not None,
        locale=caller.account.locale,
        devices=[
            DeviceView(
                id=d.id,
                name=d.name,
                status=d.status,
                created_at=d.created_at,
                last_seen_at=d.last_seen_at,
                current=d.id == caller.device.id,
            )
            for d in devices
        ],
    )


async def _own_device(session: AsyncSession, caller: Caller, device_id: str) -> Device:
    device = await session.get(Device, device_id)
    if device is None or device.account_id != caller.account.id:
        raise ApiError(404, ErrorCode.device_not_found)
    return device


async def approve_device(request: Request, session: AsyncSession, account: Account, device: Device, actor: str) -> None:
    """Shared by the in-app approval and the email link."""
    device.status = "active"
    device.approved_at = clock.now()
    audit.record(
        session,
        actor=actor,
        source="user",
        action="device_approved",
        entity="device",
        entity_id=device.id,
        new_value=device.name,
    )
    await session.commit()
    await _mail(request, session, account, "device_added", device=device.name)


@router.post(
    "/devices/{device_id}/approve",
    status_code=204,
    operation_id="approveDevice",
    responses=errors((401, "Not signed in"), (404, "No such device"), (409, "Not pending")),
)
async def approve(
    device_id: str, request: Request, caller: Caller = Depends(current_device), session: AsyncSession = Depends(get_db)
) -> Response:
    device = await _own_device(session, caller, device_id)
    if device.status != "pending":
        raise ApiError(409, ErrorCode.device_revoked if device.status == "revoked" else ErrorCode.invalid_token)
    await approve_device(request, session, caller.account, device, caller.account.email)
    return Response(status_code=204)


@router.post(
    "/devices/{device_id}/revoke",
    status_code=204,
    operation_id="revokeDevice",
    responses=errors((401, "Not signed in"), (404, "No such device")),
)
async def revoke(
    device_id: str, request: Request, caller: Caller = Depends(current_device), session: AsyncSession = Depends(get_db)
) -> Response:
    """Revokes a device (the current one signs out). Its token stops working
    immediately."""
    device = await _own_device(session, caller, device_id)
    if device.status != "revoked":
        device.status = "revoked"
        device.revoked_at = clock.now()
        device.token_hash = None
        device.claim_token_hash = None
        audit.record(
            session,
            actor=caller.account.email,
            source="user",
            action="device_revoked",
            entity="device",
            entity_id=device.id,
            new_value=device.name,
        )
        await session.commit()
        await _mail(request, session, caller.account, "device_revoked", device=device.name)
    return Response(status_code=204)


@router.post(
    "/account/verify-email/resend",
    status_code=204,
    operation_id="resendVerification",
    responses=errors((401, "Not signed in"), (503, "Email is not configured")),
)
async def resend_verification(
    request: Request, caller: Caller = Depends(current_device), session: AsyncSession = Depends(get_db)
) -> Response:
    if caller.account.email_verified_at is None:
        if not await email_configured(session):
            raise ApiError(503, ErrorCode.email_unavailable)
        link = await _link(session, caller.account, "verify", VERIFY_TTL)
        await session.commit()
        await _mail(request, session, caller.account, "verify", link=link)
    return Response(status_code=204)


async def _set_password(session: AsyncSession, account: Account, new: NewPassword) -> None:
    account.kdf_ops = new.kdf.ops
    account.kdf_mem = new.kdf.mem
    account.kdf_salt = new.kdf.salt
    account.auth_key_hash = await accounts.hash_key(new.auth_key)
    account.wrap_pw = new.wrap_pw.model_dump_json()


async def _revoke_others(session: AsyncSession, account: Account, keep: str | None) -> None:
    await session.execute(
        update(Device)
        .where(Device.account_id == account.id, Device.status != "revoked", Device.id != (keep or ""))
        .values(status="revoked", revoked_at=clock.now(), token_hash=None, claim_token_hash=None)
    )


@router.post(
    "/account/password",
    status_code=204,
    operation_id="changePassword",
    responses=errors((401, "Wrong current credentials"), (429, "Too many requests")),
)
async def change_password(
    body: PasswordChange,
    request: Request,
    caller: Caller = Depends(current_device),
    session: AsyncSession = Depends(get_db),
) -> Response:
    """Re-wraps the same vault key under a new master password. Every other
    device is signed out unless the user asks to keep them."""
    await _limit(session, request, caller.account.email)
    if not await accounts.verify_key(caller.account.auth_key_hash, body.auth_key):
        _failed(caller.account.email)
        raise ApiError(401, ErrorCode.invalid_credentials)
    await _set_password(session, caller.account, body.new)
    if not body.keep_other_devices:
        await _revoke_others(session, caller.account, keep=caller.device.id)
    audit.record(
        session,
        actor=caller.account.email,
        source="user",
        action="password_changed",
        entity="account",
        entity_id=caller.account.id,
    )
    await session.commit()
    await _mail(request, session, caller.account, "password_changed")
    return Response(status_code=204)


async def _recovery_account(session: AsyncSession, request: Request, body: RecoveryStart) -> Account:
    email = accounts.normalize_email(body.email)
    await _limit(session, request, email)
    account = await _account_by_email(session, email)
    if account is None or not await accounts.verify_key(account.recovery_auth_hash, body.recovery_auth_key):
        _failed(email)
        audit.record(
            session,
            actor=email,
            source="user",
            action="recovery_failed",
            entity="account",
            entity_id=account.id if account else None,
        )
        await session.commit()
        raise ApiError(401, ErrorCode.recovery_failed)
    if account.disabled_at is not None:
        raise ApiError(403, ErrorCode.account_disabled)
    return account


@router.post(
    "/account/recovery/start",
    response_model=RecoveryWrap,
    operation_id="startRecovery",
    responses=errors((401, "Wrong recovery key"), (429, "Too many requests")),
)
async def recovery_start(
    body: RecoveryStart, request: Request, session: AsyncSession = Depends(get_db)
) -> RecoveryWrap:
    """Proves the recovery key and returns the vault key wrapped by it."""
    account = await _recovery_account(session, request, body)
    return RecoveryWrap(vault_id=account.vault_id, wrap_rk=Sealed.model_validate_json(account.wrap_rk))


@router.post(
    "/account/recovery/complete",
    response_model=SignedIn,
    operation_id="completeRecovery",
    responses=errors((401, "Wrong recovery key"), (429, "Too many requests")),
)
async def recovery_complete(
    body: RecoveryComplete, request: Request, session: AsyncSession = Depends(get_db)
) -> SignedIn:
    """Sets a new master password with the recovery key, signs out every
    device, and signs in this one."""
    account = await _recovery_account(session, request, body)
    await _set_password(session, account, body.new)
    await _revoke_others(session, account, keep=None)
    device = await session.get(Device, body.device.id)
    if device is None:
        device = Device(
            id=body.device.id, account_id=account.id, name=body.device.name, status="active", approved_at=clock.now()
        )
        session.add(device)
    elif device.account_id != account.id:
        raise ApiError(409, ErrorCode.device_revoked)
    else:
        device.status, device.revoked_at, device.name = "active", None, body.device.name
    token = _issue_token(device)
    audit.record(
        session, actor=account.email, source="user", action="recovery_used", entity="account", entity_id=account.id
    )
    await session.commit()
    await _mail(request, session, account, "recovery_used")
    return SignedIn(
        device_token=token, email_verified=account.email_verified_at is not None, vault=_vault_keys(account)
    )
