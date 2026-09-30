"""Administrators: the first-run setup token, TOTP, and panel sessions
(docs/security-model.md, "The admin panel")."""

import hashlib
import hmac
import logging
import secrets
import time
from dataclasses import dataclass
from datetime import timedelta

import pyotp
import segno
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app import accounts, clock, crypto
from app.models import Admin, AdminSession

logger = logging.getLogger("tildeck.admin")

ISSUER = "Tildeck"
SESSION_COOKIE = "tildeck_admin"
SESSION_IDLE = timedelta(minutes=30)
SESSION_MAX = timedelta(hours=12)
# Codes from the previous and the next 30-second step are accepted, for clock
# drift between the server and the authenticator.
TOTP_WINDOW = 1
PENDING_TTL = 10 * 60


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8", errors="replace")).hexdigest()


@dataclass
class _PendingAdmin:
    username: str
    password_hash: str
    secret: str
    expires: float


class SetupState:
    """The one-time setup token of a server without administrators. A new
    token is made at each start while no administrator exists, printed to the
    log, and forgotten as soon as the first administrator is created. Only
    its hash stays in memory."""

    def __init__(self) -> None:
        self._token_hash: str | None = None
        self._pending: _PendingAdmin | None = None

    @property
    def open(self) -> bool:
        return self._token_hash is not None

    def issue(self) -> str:
        token = secrets.token_urlsafe(24)
        self._token_hash = _hash(token)
        self._pending = None
        return token

    def close(self) -> None:
        self._token_hash = None
        self._pending = None

    def matches(self, token: str) -> bool:
        return self._token_hash is not None and hmac.compare_digest(self._token_hash, _hash(token))

    def begin(self, username: str, password_hash: str) -> str:
        secret = pyotp.random_base32()
        self._pending = _PendingAdmin(username, password_hash, secret, time.monotonic() + PENDING_TTL)
        return secret

    def pending(self) -> _PendingAdmin | None:
        if self._pending is not None and self._pending.expires < time.monotonic():
            self._pending = None
        return self._pending


setup = SetupState()


async def admin_count(session: AsyncSession) -> int:
    return await session.scalar(select(func.count()).select_from(Admin)) or 0


async def ensure_setup_token(session: AsyncSession) -> str | None:
    """Called at startup. Prints a setup token while no administrator exists."""
    if await admin_count(session) > 0:
        setup.close()
        return None
    token = setup.issue()
    logger.warning(
        "No administrator yet. Open the admin panel and use this one-time setup token: %s "
        "(a new one is printed at every start until the first administrator exists)",
        token,
    )
    return token


def otpauth_uri(secret: str, username: str) -> str:
    return pyotp.TOTP(secret).provisioning_uri(name=username, issuer_name=ISSUER)


def qr_svg(uri: str) -> str:
    """The provisioning address as an SVG QR code, for authenticator apps."""
    return segno.make(uri, error="m").svg_inline(scale=5, border=2, dark="#0b1f1c", light="#ffffff")


def _now() -> float:
    return time.time()


def totp_step(secret: str, code: str, last_step: int | None, now: float | None = None) -> int | None:
    """The time step [code] belongs to, or None. A step at or before
    [last_step] was already used, so a replayed code is refused."""
    code = code.strip().replace(" ", "")
    if len(code) != 6 or not code.isdigit():
        return None
    totp = pyotp.TOTP(secret)
    now = _now() if now is None else now
    current = int(now) // totp.interval
    for step in range(current - TOTP_WINDOW, current + TOTP_WINDOW + 1):
        if last_step is not None and step <= last_step:
            continue
        if hmac.compare_digest(totp.at(step * totp.interval), code):
            return step
    return None


async def open_session(session: AsyncSession, admin: Admin) -> tuple[str, str]:
    """A new session: the cookie token and its CSRF token."""
    token = secrets.token_urlsafe(32)
    csrf = secrets.token_urlsafe(32)
    now = clock.now()
    session.add(
        AdminSession(token_hash=_hash(token), admin_id=admin.id, csrf_token=csrf, created_at=now, last_seen_at=now)
    )
    return token, csrf


async def session_of(session: AsyncSession, token: str | None) -> tuple[AdminSession, Admin] | None:
    """The live session for a cookie token, refreshed; None when missing,
    expired, or its administrator is disabled. An expired session is removed."""
    if not token:
        return None
    row = await session.get(AdminSession, _hash(token))
    if row is None:
        return None
    now = clock.now()
    if now - row.last_seen_at > SESSION_IDLE or now - row.created_at > SESSION_MAX:
        await session.delete(row)
        await session.commit()
        return None
    admin = await session.get(Admin, row.admin_id)
    if admin is None or admin.disabled_at is not None:
        return None
    row.last_seen_at = now
    return row, admin


async def close_session(session: AsyncSession, token: str | None) -> None:
    if token:
        row = await session.get(AdminSession, _hash(token))
        if row is not None:
            await session.delete(row)


def new_admin(username: str, password_hash: str, secret: str, step: int) -> Admin:
    return Admin(
        id=accounts.new_id(),
        username=username,
        password_hash=password_hash,
        totp_secret_encrypted=crypto.encrypt(secret),
        totp_last_step=step,
    )


def secret_of(admin: Admin) -> str:
    return crypto.decrypt(admin.totp_secret_encrypted)
