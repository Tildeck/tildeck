"""Bootstrap configuration.

Only values that the process needs before it can reach the database or read
its stored settings live here. Everything else is a managed setting
(app/settings_store.py): editable in the admin panel, where a set environment
variable wins and locks the field.
"""

import os
from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict

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

    def production_problems(self) -> list[str]:
        """Reasons this configuration must not run in production. Enforced
        only when APP_ENV is production; development may use example values."""
        problems: list[str] = []
        if _is_placeholder(self.CONFIG_ENCRYPTION_KEY):
            problems.append("CONFIG_ENCRYPTION_KEY is empty or a placeholder")
        elif len(self.CONFIG_ENCRYPTION_KEY.strip()) < MIN_KEY_LENGTH:
            problems.append(f"CONFIG_ENCRYPTION_KEY is too short: at least {MIN_KEY_LENGTH} characters are required")
        if _is_placeholder(self.DATABASE_URL):
            problems.append("DATABASE_URL contains a placeholder")
        return problems


def _is_placeholder(value: str) -> bool:
    lowered = value.strip().lower()
    if not lowered:
        return True
    return any(marker in lowered for marker in PLACEHOLDER_MARKERS)


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
