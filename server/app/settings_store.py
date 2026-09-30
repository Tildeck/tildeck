"""Managed settings: the single read and write path.

Every operator setting is declared once in REGISTRY and is editable in the
admin panel. A set environment variable wins over the database and locks the
field; writes to a locked field are refused. Values are stored encrypted at
rest, secret or not. A secret value never leaves the server through any API,
not even when it comes from the environment: callers see only its state.
"""

import logging
import os
import re
from dataclasses import dataclass
from urllib.parse import urlparse

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app import audit, crypto
from app.models import Setting

logger = logging.getLogger("tildeck.settings")

REDACTED = "(secret)"


@dataclass(frozen=True)
class SettingSpec:
    key: str
    secret: bool = False
    env_var: str | None = None
    default: str | None = None
    description: str = ""
    kind: str = "text"  # text | choice (one of choices)
    choices: tuple[str, ...] | None = None


REGISTRY: dict[str, SettingSpec] = {
    spec.key: spec
    for spec in (
        SettingSpec(
            key="public_url",
            env_var="PUBLIC_URL",
            description="The https address clients and emails use to reach this server",
        ),
        SettingSpec(
            key="registration_mode",
            env_var="REGISTRATION_MODE",
            default="closed",
            kind="choice",
            choices=("closed", "invite", "open"),
            description="Who may create an account: nobody, invited people, or anyone",
        ),
        SettingSpec(key="smtp_host", env_var="SMTP_HOST", description="SMTP server host name"),
        SettingSpec(key="smtp_port", env_var="SMTP_PORT", default="587", description="SMTP server port"),
        SettingSpec(
            key="smtp_security",
            env_var="SMTP_SECURITY",
            default="starttls",
            kind="choice",
            choices=("starttls", "tls", "none"),
            description="How the SMTP connection is encrypted; none only for a relay on the same host or a private network",
        ),
        SettingSpec(key="smtp_username", env_var="SMTP_USERNAME", description="SMTP user name"),
        SettingSpec(key="smtp_password", secret=True, env_var="SMTP_PASSWORD", description="SMTP password"),
        SettingSpec(key="smtp_from", env_var="SMTP_FROM", description="Sender address of every email"),
        SettingSpec(
            key="device_idle_days",
            env_var="DEVICE_IDLE_DAYS",
            default="90",
            description="Days a device may stay unused before it must sign in again",
        ),
        SettingSpec(
            key="signin_limit_per_account",
            env_var="SIGNIN_LIMIT_PER_ACCOUNT",
            default="10",
            description="Failed sign-in and recovery attempts allowed per account in 15 minutes",
        ),
        SettingSpec(
            key="signin_limit_per_address",
            env_var="SIGNIN_LIMIT_PER_ADDRESS",
            default="30",
            description="Account requests allowed per client address in 15 minutes",
        ),
    )
}


class UnknownSetting(KeyError):
    pass


class SettingLocked(RuntimeError):
    """The value comes from the environment; the panel cannot change it."""


class InvalidSettingValue(ValueError):
    """The value is not acceptable for this setting."""


def _validate_url(key: str, value: str) -> None:
    parsed = urlparse(value)
    if parsed.scheme not in ("https", "http") or not parsed.netloc:
        raise InvalidSettingValue(key)


def _validate_port(key: str, value: str) -> None:
    if not value.isdigit() or not 1 <= int(value) <= 65535:
        raise InvalidSettingValue(key)


_EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _validate_email(key: str, value: str) -> None:
    if not _EMAIL.match(value):
        raise InvalidSettingValue(key)


def _validate_positive_int(key: str, value: str) -> None:
    if not value.isdigit() or int(value) < 1:
        raise InvalidSettingValue(key)


VALIDATORS = {
    "public_url": _validate_url,
    "smtp_port": _validate_port,
    "smtp_from": _validate_email,
    "device_idle_days": _validate_positive_int,
    "signin_limit_per_account": _validate_positive_int,
    "signin_limit_per_address": _validate_positive_int,
}


def _spec(key: str) -> SettingSpec:
    try:
        return REGISTRY[key]
    except KeyError:
        raise UnknownSetting(key) from None


def env_value(spec: SettingSpec) -> str | None:
    if spec.env_var:
        raw = os.environ.get(spec.env_var, "").strip()
        if raw:
            return raw
    return None


async def get_value(session: AsyncSession, key: str) -> str | None:
    """The effective value: environment, then database, then default."""
    spec = _spec(key)
    from_env = env_value(spec)
    if from_env is not None:
        return from_env
    row = await session.get(Setting, key)
    if row is not None:
        return crypto.decrypt(row.value_encrypted)
    return spec.default


async def set_value(session: AsyncSession, key: str, value: str, *, actor: str, source: str = "user") -> None:
    """Store a value and log the change. Raises SettingLocked when the
    environment owns the field."""
    spec = _spec(key)
    if env_value(spec) is not None:
        raise SettingLocked(key)
    if spec.choices is not None and value not in spec.choices:
        raise InvalidSettingValue(key)
    validate = VALIDATORS.get(key)
    if validate is not None and value:
        validate(key, value)
    row = await session.get(Setting, key)
    if row is None:
        old_plain = None
        row = Setting(key=key, is_secret=spec.secret, value_encrypted=crypto.encrypt(value), updated_by=actor)
        session.add(row)
    else:
        old_plain = crypto.decrypt(row.value_encrypted)
        # A no-op write must not log or re-encrypt.
        if old_plain == value:
            return
        row.value_encrypted = crypto.encrypt(value)
        row.updated_by = actor
    audit.record(
        session,
        actor=actor,
        source=source,
        action="setting_changed",
        entity="setting",
        entity_id=key,
        old_value=REDACTED if spec.secret and old_plain is not None else old_plain,
        new_value=REDACTED if spec.secret else value,
    )


async def describe_all(session: AsyncSession) -> list[dict]:
    """The admin listing. A secret's value never leaves the server, whatever
    its origin: the entry says only whether it is configured and where the
    value comes from."""
    rows = {row.key: row for row in (await session.scalars(select(Setting))).all()}
    described = []
    for spec in REGISTRY.values():
        from_env = env_value(spec)
        stored = rows.get(spec.key)
        if from_env is not None:
            origin = "env"
        elif stored is not None:
            origin = "database"
        else:
            origin = "default"
        entry = {
            "key": spec.key,
            "secret": spec.secret,
            "kind": spec.kind,
            "choices": list(spec.choices) if spec.choices else None,
            "locked": from_env is not None,
            "origin": origin,
            "configured": from_env is not None or stored is not None or spec.default is not None,
            "description": spec.description,
        }
        if not spec.secret:
            entry["value"] = await get_value(session, spec.key)
        described.append(entry)
    return described


async def assert_startup_state(session: AsyncSession) -> None:
    """Every stored value must decrypt with the current key. In production a
    failure aborts startup; in development it is logged loudly and the broken
    rows stay unreadable until the key is restored."""
    from app.config import get_settings

    broken = []
    for row in (await session.scalars(select(Setting))).all():
        try:
            crypto.decrypt(row.value_encrypted)
        except crypto.DecryptionFailed:
            broken.append(row.key)
    if broken:
        message = (
            "stored settings cannot be decrypted with the current CONFIG_ENCRYPTION_KEY: "
            + ", ".join(sorted(broken))
            + ". Restore the original key, or set a new one and re-enter the values."
        )
        if get_settings().APP_ENV == "production":
            raise RuntimeError(message)
        logger.error("%s", message)
