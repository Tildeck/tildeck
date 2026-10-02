"""Accounts and devices: the server side of docs/security-model.md.

The server never sees a master password, a vault key, or plaintext records.
It stores Argon2id hashes of the authentication and recovery keys, the two
wrapped vault keys, and the KDF parameters the client chose.
"""

import base64
import hashlib
import hmac
import re
import secrets
import time
import uuid
from collections import defaultdict, deque
from datetime import timedelta
from functools import lru_cache

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from pydantic import BaseModel, Field, field_validator
from starlette.concurrency import run_in_threadpool

from app import clock
from app.config import get_settings

# The server hashes keys that are already high-entropy (256 bits derived
# with Argon2id on the client), so moderate server parameters suffice; they
# still make a stolen database useless for signing in.
_hasher = PasswordHasher(time_cost=2, memory_cost=19456, parallelism=1)

MIN_KDF_OPS = 3
MIN_KDF_MEM = 64 * 1024 * 1024
DEFAULT_KDF = {"ops": MIN_KDF_OPS, "mem": MIN_KDF_MEM}

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _b64(value: str, *, length: int | None = None, min_length: int | None = None) -> bytes:
    try:
        raw = base64.b64decode(value, validate=True)
    except ValueError:
        raise ValueError("not base64") from None
    if length is not None and len(raw) != length:
        raise ValueError(f"must decode to {length} bytes")
    if min_length is not None and len(raw) < min_length:
        raise ValueError(f"must decode to at least {min_length} bytes")
    return raw


class KdfParams(BaseModel):
    """Argon2id parameters chosen by the client; the server enforces the
    minimum of the security model and stores them for the next sign-in."""

    alg: str = Field(pattern="^argon2id13$")
    ops: int = Field(ge=MIN_KDF_OPS, le=20)
    mem: int = Field(ge=MIN_KDF_MEM, le=1024 * 1024 * 1024)
    salt: str

    @field_validator("salt")
    @classmethod
    def _salt(cls, v: str) -> str:
        _b64(v, length=16)
        return v


class Sealed(BaseModel):
    """A nonce and a ciphertext, opaque to the server."""

    nonce: str
    ct: str

    @field_validator("nonce")
    @classmethod
    def _nonce(cls, v: str) -> str:
        _b64(v, length=24)
        return v

    @field_validator("ct")
    @classmethod
    def _ct(cls, v: str) -> str:
        _b64(v, min_length=16)
        return v


def key32(v: str) -> str:
    _b64(v, length=32)
    return v


def normalize_email(email: str) -> str:
    return email.strip().lower()


async def hash_key(key_b64: str) -> str:
    return await run_in_threadpool(_hasher.hash, key_b64)


@lru_cache
def _absent_hash() -> str:
    return _hasher.hash(secrets.token_urlsafe(32))


async def verify_key(stored_hash: str | None, key_b64: str) -> bool:
    """Whether key_b64 matches stored_hash. Without a stored hash (no such
    account or administrator) it still verifies, against a throwaway hash,
    so the answer takes as long and does not tell who exists."""

    def check() -> bool:
        try:
            return _hasher.verify(stored_hash or _absent_hash(), key_b64) and stored_hash is not None
        except VerificationError, InvalidHashError:
            return False

    return await run_in_threadpool(check)


def new_token() -> tuple[str, str]:
    """A random 256-bit token and the SHA-256 the server keeps of it."""
    token = secrets.token_urlsafe(32)
    return token, token_hash(token)


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("ascii", errors="replace")).hexdigest()


def new_id() -> str:
    return str(uuid.uuid4())


def fake_salt(email: str) -> str:
    """A stable salt for an address with no account, so pre-login answers
    look the same whether or not the account exists. Keyed with a sub-key of
    the settings encryption key, which only the server has."""
    key = hmac.new(
        get_settings().CONFIG_ENCRYPTION_KEY.encode("utf-8"), b"tildeck:prelogin:v1", hashlib.sha256
    ).digest()
    digest = hmac.new(key, normalize_email(email).encode("utf-8"), hashlib.sha256).digest()
    return base64.b64encode(digest[:16]).decode("ascii")


def expires_in(delta: timedelta):
    return clock.now() + delta


class RateLimiter:
    """Counts events per key in a sliding 15-minute window, in memory.

    One server process holds the counters; a restart resets them. That is
    acceptable for the single-container deployment: an attacker gains one
    fresh window per restart, and restarts are visible to the operator.
    """

    WINDOW = 15 * 60

    def __init__(self) -> None:
        self._events: dict[str, deque[float]] = defaultdict(deque)

    def _trim(self, key: str, now: float) -> deque[float]:
        events = self._events[key]
        while events and events[0] <= now - self.WINDOW:
            events.popleft()
        return events

    def exceeded(self, key: str, limit: int) -> bool:
        return len(self._trim(key, time.monotonic())) >= limit

    def hit(self, key: str) -> None:
        now = time.monotonic()
        self._trim(key, now).append(now)

    def take(self, key: str, limit: int) -> bool:
        """Counts an attempt unless key is already at limit; False when it
        is. Check and count happen together, so concurrent attempts cannot
        all pass the check before any of them is counted."""
        if self.exceeded(key, limit):
            return False
        self.hit(key)
        return True

    def give_back(self, key: str) -> None:
        """Uncounts the latest attempt: it turned out to be a success."""
        events = self._events.get(key)
        if events:
            events.pop()

    def reset(self) -> None:
        self._events.clear()
