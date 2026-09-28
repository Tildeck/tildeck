"""Programmatic Alembic runner.

There is no alembic.ini: the configuration is built here so the startup
lifespan, the tests and the scripts all run migrations the same way. Runs in
a worker thread because the async env.py needs its own event loop.
"""

import asyncio
import logging
import threading
from contextlib import contextmanager
from pathlib import Path

from alembic import command
from alembic.config import Config

logger = logging.getLogger("tildeck.migrations")

# A constant, arbitrary key: every process of this application competes for
# the same PostgreSQL advisory lock, and nothing else in the database uses it.
# Session level, so it is released the moment the holder's connection goes
# away, including a container that was killed mid-migration.
MIGRATION_LOCK_KEY = 0x54494C44  # "TILD"


def make_config() -> Config:
    cfg = Config()
    cfg.set_main_option("script_location", str(Path(__file__).parent / "migrations"))
    return cfg


def _dsn() -> str:
    """The database URL as asyncpg wants it: no SQLAlchemy dialect prefix."""
    from app.config import get_settings

    url = get_settings().DATABASE_URL
    scheme, _, rest = url.partition("://")
    return f"{scheme.split('+', 1)[0]}://{rest}"


@contextmanager
def _advisory_lock():
    """Hold the migration lock for the duration of the block, so two
    containers starting together never run Alembic concurrently against one
    database. The lock lives on its own connection in its own thread, because
    the guarded block is synchronous Alembic code with an event loop of its own.
    """
    acquired = threading.Event()
    release = threading.Event()
    failure: list[BaseException] = []

    async def hold() -> None:
        import asyncpg

        connection = await asyncpg.connect(_dsn())
        try:
            await connection.execute("SELECT pg_advisory_lock($1)", MIGRATION_LOCK_KEY)
            acquired.set()
            await asyncio.to_thread(release.wait)
            await connection.execute("SELECT pg_advisory_unlock($1)", MIGRATION_LOCK_KEY)
        finally:
            await connection.close()

    def run() -> None:
        try:
            asyncio.run(hold())
        except BaseException as exc:  # noqa: BLE001 - reported to the caller below
            failure.append(exc)
        finally:
            acquired.set()

    holder = threading.Thread(target=run, name="migration-advisory-lock", daemon=True)
    holder.start()
    acquired.wait()
    if failure:
        raise failure[0]
    try:
        yield
    finally:
        release.set()
        holder.join(timeout=30)
        if failure:
            logger.warning("Releasing the migration advisory lock failed: %s", failure[0])


def upgrade_to_head() -> None:
    with _advisory_lock():
        command.upgrade(make_config(), "head")


def current_head() -> str:
    """The newest revision in the code, for scripts that snapshot a database
    before applying newer migrations."""
    from alembic.script import ScriptDirectory

    return ScriptDirectory.from_config(make_config()).get_current_head() or ""


if __name__ == "__main__":
    upgrade_to_head()
