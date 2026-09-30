"""Shared fixtures.

Tests run against a real PostgreSQL only. The connection is forced to a
dedicated test database BEFORE any app import, so a developer .env can never
leak a real database into a test run, and the database name must end with
_test as a second guard.
"""

import os
import tempfile

os.environ["DATABASE_URL"] = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+asyncpg://tildeck:tildeck@localhost:5432/tildeck_test",
)
os.environ["APP_ENV"] = "development"
os.environ["CONFIG_ENCRYPTION_KEY"] = "test-config-encryption-key-for-pytest-only"
os.environ.pop("APP_VERSION", None)
# No built panel in the test image: an empty directory keeps the API-only path.
os.environ["PANEL_DIR"] = tempfile.mkdtemp(prefix="tildeck-panel-")

# Managed settings read the environment first. A variable left over from the
# machine running the tests would lock a field and change what a test sees.
for _var in (
    "PUBLIC_URL",
    "REGISTRATION_MODE",
    "SMTP_HOST",
    "SMTP_PORT",
    "SMTP_SECURITY",
    "SMTP_USERNAME",
    "SMTP_PASSWORD",
    "SMTP_FROM",
    "DEVICE_IDLE_DAYS",
    "SIGNIN_LIMIT_PER_ACCOUNT",
    "SIGNIN_LIMIT_PER_ADDRESS",
):
    os.environ.pop(_var, None)

if not os.environ["DATABASE_URL"].rsplit("/", 1)[-1].endswith("_test"):
    raise RuntimeError("Refusing to run tests: the database name must end with _test")

import pytest  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402


@pytest.fixture(scope="session", autouse=True)
def _migrate():
    """Bring the test database to head before anything else runs."""
    from app.migrations_runner import upgrade_to_head

    upgrade_to_head()


@pytest.fixture
async def session():
    from app.db import async_session

    async with async_session() as s:
        yield s
        await s.rollback()


@pytest.fixture
async def client():
    from app.main import app

    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c
