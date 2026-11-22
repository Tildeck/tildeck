"""Shared fixtures.

Tests run against a real PostgreSQL only. The connection is forced to a
dedicated test database BEFORE the app reads its settings, so a developer
.env can never leak a real database into a test run, and the database name
must end with _test as a second guard.

The database URL and the settings encryption key have no defaults: a test
run gets one-time values from scripts/verify.sh (TEST_DATABASE_URL,
TEST_CONFIG_ENCRYPTION_KEY) and refuses to start without them.
"""

import os
import tempfile

from sqlalchemy.engine import make_url

from app.config import MIN_KEY_LENGTH, database_url_problem, generated_value_problem, variant_spellings

_HOW = "scripts/verify.sh --area server generates it for each run"

_problem = database_url_problem(os.environ.get("TEST_DATABASE_URL"), password_required=True)
if _problem:
    raise RuntimeError(f"Refusing to run tests: TEST_DATABASE_URL {_problem}; {_HOW}")
if not make_url(os.environ["TEST_DATABASE_URL"]).database.endswith("_test"):
    raise RuntimeError("Refusing to run tests: the database name in TEST_DATABASE_URL must end with _test")
_problem = generated_value_problem(os.environ.get("TEST_CONFIG_ENCRYPTION_KEY"), min_length=MIN_KEY_LENGTH)
if _problem:
    raise RuntimeError(f"Refusing to run tests: TEST_CONFIG_ENCRYPTION_KEY {_problem}; {_HOW}")

# Settings reads names case-insensitively: another spelling left in the
# environment (database_url) could win over the values set here.
for _var in ("DATABASE_URL", "CONFIG_ENCRYPTION_KEY", "APP_ENV"):
    for _other in variant_spellings(os.environ, _var):
        del os.environ[_other]

os.environ["DATABASE_URL"] = os.environ["TEST_DATABASE_URL"]
os.environ["APP_ENV"] = "development"
os.environ["CONFIG_ENCRYPTION_KEY"] = os.environ["TEST_CONFIG_ENCRYPTION_KEY"]
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
