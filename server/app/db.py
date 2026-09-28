"""Async SQLAlchemy engine and session factory."""

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from app.config import get_settings


class Base(DeclarativeBase):
    """Declarative base for every model. Alembic autogenerate reads its metadata."""


# Connections are recycled every 30 minutes and checked before use, so a
# connection dropped by the network or by a database restart surfaces as a
# retry, not as an error. pool_timeout keeps a request from queueing for long
# behind a saturated pool, and command_timeout caps a single statement.
engine = create_async_engine(
    get_settings().DATABASE_URL,
    pool_size=10,
    max_overflow=5,
    pool_timeout=5,
    pool_recycle=1800,
    pool_pre_ping=True,
    connect_args={"command_timeout": 30},
)
async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


async def get_db():
    """FastAPI dependency yielding a request-scoped session."""
    async with async_session() as session:
        yield session
