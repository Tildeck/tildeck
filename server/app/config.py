"""Bootstrap configuration.

Only values that the process needs before it can reach the database or read
its stored settings live here. Everything else is a managed setting
(app/settings_store.py): editable in the admin panel, where a set environment
variable wins and locks the field.
"""

import os
import re
from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import make_url

# Values that must never survive into a production process. Matched as
# substrings, case-insensitive, so every placeholder style in .env.example
# is caught.
PLACEHOLDER_MARKERS = ("change-me", "placeholder", "example")

# Minimum length of the key that protects the stored settings. The generator
# documented in .env.example produces 64 characters, so a value below this
# was typed, not generated.
MIN_KEY_LENGTH = 32


class Settings(BaseSettings):
    model_config = SettingsConfigDict(extra="ignore")

    DATABASE_URL: str
    APP_ENV: Literal["development", "production"] = "development"
    CONFIG_ENCRYPTION_KEY: str
    # Directory INSIDE the container holding the built admin panel. The image
    # ships it; a checkout running outside a container may point elsewhere or
    # leave it missing, in which case only the API is served.
    PANEL_DIR: str = "/app/panel"
    # Peers whose X-Forwarded-For and X-Forwarded-Proto are believed: the
    # reverse proxy in front of the server. Comma-separated addresses or
    # networks. The default covers a proxy on this host or in a private
    # network (Docker's included); a client reaching the server directly
    # from a public address cannot choose the address its limits count.
    TRUSTED_PROXIES: str = "127.0.0.0/8,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,fc00::/7"

    def production_problems(self) -> list[str]:
        """Reasons this configuration must not run in production. Enforced
        only when APP_ENV is production; development may use example values."""
        problems: list[str] = []
        if is_placeholder(self.CONFIG_ENCRYPTION_KEY):
            problems.append("CONFIG_ENCRYPTION_KEY is empty or a placeholder")
        elif len(self.CONFIG_ENCRYPTION_KEY.strip()) < MIN_KEY_LENGTH:
            problems.append(f"CONFIG_ENCRYPTION_KEY is too short: at least {MIN_KEY_LENGTH} characters are required")
        if is_placeholder(self.DATABASE_URL):
            problems.append("DATABASE_URL contains a placeholder")
        return problems


def is_placeholder(value: str) -> bool:
    lowered = value.strip().lower()
    if not lowered:
        return True
    return any(marker in lowered for marker in PLACEHOLDER_MARKERS)


# Checks for the values that the tests, the contract export, and the
# development stack generate for themselves (scripts/verify.sh,
# scripts/local.sh). The production startup check above is separate.

# Values that were once committed to this repository as test or export
# defaults. They are public, so a generated value must never equal one.
RETIRED_VALUES = frozenset({"tildeck", "test-config-encryption-key-for-pytest-only", "openapi-export-only"})

# The only shape a generated database URL takes. Every separator has one
# reading, so SQLAlchemy, asyncpg (app/migrations_runner.py), and Alembic
# (app/migrations/env.py) all see the same user, password, host, and
# database: no query (asyncpg applies it after the URL parts), no fragment,
# no percent-encoding (Alembic's config would interpolate it), no second
# host or "@".
_GENERATED_URL = re.compile(
    r"(?P<scheme>[a-z0-9+]+)://(?P<user>[A-Za-z0-9_.-]+)(?::(?P<password>[A-Za-z0-9_.-]+))?"
    r"@(?P<host>[A-Za-z0-9_.-]+)(?::(?P<port>[0-9]+))?/(?P<database>[A-Za-z0-9_]+)"
)


def secret_problem(value: str | None, *, min_length: int = 0) -> str | None:
    """Why a generated secret is not acceptable, or None. Never includes the
    value. Stripped first, as app/crypto.py strips the key."""
    value = (value or "").strip()
    if not value:
        return "is not set"
    if is_placeholder(value):
        return "is a placeholder"
    if value in RETIRED_VALUES:
        return "is a value once published in this repository"
    if len(value) < min_length:
        return f"is too short: at least {min_length} characters are required"
    return None


def database_url_problem(url: str | None, *, password_required: bool) -> str | None:
    """Why a generated database URL is not acceptable, or None. Never
    includes any part of the URL."""
    if not (url or "").strip():
        return "is not set"
    match = _GENERATED_URL.fullmatch(url)
    if match is None:
        return "must have the generated form: user, password, host, port, and database of letters, digits, _ . - only"
    try:
        parsed = make_url(url)
    except Exception:
        return "cannot be parsed"
    port = match["port"]
    if (parsed.username, parsed.password, parsed.host, parsed.port, parsed.database) != (
        match["user"],
        match["password"],
        match["host"],
        int(port) if port else None,
        match["database"],
    ):
        return "cannot be parsed"
    if match["password"] is not None or password_required:
        problem = secret_problem(match["password"])
        if problem:
            return f"password {problem}"
    return None


@lru_cache
def get_settings() -> Settings:
    return Settings()


def get_app_version() -> str:
    """The running version.

    Docker images carry it as APP_VERSION (build argument). A checkout reads
    the repo-root VERSION file, which is the single source of truth.
    """
    from_env = os.environ.get("APP_VERSION", "").strip()
    if from_env:
        return from_env
    version_file = Path(__file__).resolve().parents[2] / "VERSION"
    try:
        return version_file.read_text(encoding="utf-8").strip() or "0.0.0"
    except OSError:
        return "0.0.0"
