"""The activity log write path. Append-only by design: nothing in the
application updates or deletes an entry, and no API route exists for that."""

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import AuditEntry

SOURCES = ("user", "admin", "system")


def record(
    session: AsyncSession,
    *,
    actor: str,
    source: str,
    action: str,
    entity: str,
    entity_id: str | None = None,
    old_value: str | None = None,
    new_value: str | None = None,
) -> AuditEntry:
    """Add an entry to the session. Committed with the caller's transaction,
    so the change and its log line land atomically or not at all."""
    if source not in SOURCES:
        raise ValueError(f"unknown audit source: {source}")
    entry = AuditEntry(
        actor=actor,
        source=source,
        action=action,
        entity=entity,
        entity_id=entity_id,
        old_value=old_value,
        new_value=new_value,
    )
    session.add(entry)
    return entry
