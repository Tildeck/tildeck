"""Database models."""

from datetime import datetime

from sqlalchemy import BigInteger, Boolean, DateTime, ForeignKey, Index, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class Setting(Base):
    """One managed setting. The value is always stored encrypted at rest,
    secret or not: one code path, no chance of a secret in a plain column."""

    __tablename__ = "settings"

    key: Mapped[str] = mapped_column(String(100), primary_key=True)
    value_encrypted: Mapped[str] = mapped_column(Text)
    is_secret: Mapped[bool] = mapped_column(Boolean, default=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    updated_by: Mapped[str] = mapped_column(String(200))


class AuditEntry(Base):
    """Append-only activity log. No API updates or deletes it, ever.

    old_value and new_value hold the readable values for regular fields and
    a redaction marker for secrets; the writing service enforces that."""

    __tablename__ = "audit_entries"
    __table_args__ = (Index("ix_audit_entries_at", "at"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    actor: Mapped[str] = mapped_column(String(200))
    source: Mapped[str] = mapped_column(String(20))
    action: Mapped[str] = mapped_column(String(100))
    entity: Mapped[str] = mapped_column(String(100))
    entity_id: Mapped[str | None] = mapped_column(String(200), nullable=True)
    old_value: Mapped[str | None] = mapped_column(Text, nullable=True)
    new_value: Mapped[str | None] = mapped_column(Text, nullable=True)


class Account(Base):
    """A user account. The server holds only what docs/security-model.md
    allows: hashes of the authentication and recovery keys, the wrapped vault
    key (twice), and the KDF parameters. Nothing here decrypts a vault."""

    __tablename__ = "accounts"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    email: Mapped[str] = mapped_column(String(320), unique=True)
    email_verified_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    disabled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    locale: Mapped[str] = mapped_column(String(8))
    vault_id: Mapped[str] = mapped_column(String(36))
    kdf_ops: Mapped[int] = mapped_column(Integer)
    kdf_mem: Mapped[int] = mapped_column(Integer)
    kdf_salt: Mapped[str] = mapped_column(String(64))
    auth_key_hash: Mapped[str] = mapped_column(Text)
    recovery_auth_hash: Mapped[str] = mapped_column(Text)
    wrap_pw: Mapped[str] = mapped_column(Text)
    wrap_rk: Mapped[str] = mapped_column(Text)
    # Two-factor sign-in: the active TOTP secret, one being enrolled until a
    # code from it is confirmed, both encrypted with the config key, and the
    # last accepted time step (a code works once).
    totp_secret_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
    totp_pending_encrypted: Mapped[str | None] = mapped_column(Text, nullable=True)
    totp_last_step: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    # The last revision assigned to one of this account's records.
    revision: Mapped[int] = mapped_column(BigInteger, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Device(Base):
    """One device of an account. Its bearer token and its one-time claim token
    are stored as SHA-256 hashes only."""

    __tablename__ = "devices"
    __table_args__ = (Index("ix_devices_account", "account_id"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"))
    name: Mapped[str] = mapped_column(String(100))
    status: Mapped[str] = mapped_column(String(10))  # pending | active | revoked
    token_hash: Mapped[str | None] = mapped_column(String(64), unique=True, nullable=True)
    claim_token_hash: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class EmailToken(Base):
    """A one-time link sent by email: address verification, or approval of a
    pending device. Stored as a SHA-256 hash; single use; expires."""

    __tablename__ = "email_tokens"

    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    purpose: Mapped[str] = mapped_column(String(10))  # verify | approve
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"))
    device_id: Mapped[str | None] = mapped_column(ForeignKey("devices.id", ondelete="CASCADE"), nullable=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class Record(Base):
    """One encrypted vault record. The server sees only its id, its version
    (set by the client and enforced here), the account-wide revision it was
    stored at (the pull cursor), a tombstone flag, and opaque ciphertext."""

    __tablename__ = "records"
    __table_args__ = (Index("ix_records_account_revision", "account_id", "revision"),)

    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"), primary_key=True)
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    version: Mapped[int] = mapped_column(Integer)
    revision: Mapped[int] = mapped_column(BigInteger)
    deleted: Mapped[bool] = mapped_column(Boolean, default=False)
    nonce: Mapped[str | None] = mapped_column(String(64), nullable=True)
    ct: Mapped[str | None] = mapped_column(Text, nullable=True)
    device_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Admin(Base):
    """An administrator of the admin panel. Separate from user accounts and
    never holds a vault. The password is an Argon2id hash; the TOTP secret is
    encrypted with the settings encryption key."""

    __tablename__ = "admins"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    username: Mapped[str] = mapped_column(String(100), unique=True)
    password_hash: Mapped[str] = mapped_column(Text)
    totp_secret_encrypted: Mapped[str] = mapped_column(Text)
    # The last TOTP time step accepted: a code is never accepted twice.
    totp_last_step: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    disabled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class AdminSession(Base):
    """A signed-in panel session. The cookie holds the token; the server keeps
    only its SHA-256, so signing out and expiry take effect at once."""

    __tablename__ = "admin_sessions"

    token_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    admin_id: Mapped[str] = mapped_column(ForeignKey("admins.id", ondelete="CASCADE"))
    csrf_token: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class Invite(Base):
    """An invitation to register, created by an administrator for one email
    address. The code is stored as a SHA-256 hash only; single use; expires.
    Registering with it confirms the address: the administrator vouched."""

    __tablename__ = "invites"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    code_hash: Mapped[str] = mapped_column(String(64), unique=True)
    email: Mapped[str] = mapped_column(String(320))
    created_by: Mapped[str] = mapped_column(String(100))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
