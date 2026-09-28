"""Database models."""

from datetime import datetime

from sqlalchemy import Boolean, DateTime, Index, String, Text, func
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
