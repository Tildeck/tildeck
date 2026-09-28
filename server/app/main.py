"""Application entry point: uvicorn app.main:app."""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from starlette.concurrency import run_in_threadpool

from app import migrations_runner, panel, settings_store
from app.config import get_app_version, get_settings
from app.db import async_session
from app.routers import health

# Uvicorn configures only its own loggers. Without this every app log line
# below WARNING is dropped.
logging.basicConfig(level=logging.INFO, format="%(levelname)s:     %(name)s - %(message)s")
logger = logging.getLogger("tildeck")


def assert_startup_config() -> None:
    """Refuse to start a production process on placeholder configuration."""
    settings = get_settings()
    if settings.APP_ENV != "production":
        return
    problems = settings.production_problems()
    if problems:
        raise RuntimeError("Refusing to start in production: " + "; ".join(problems))


@asynccontextmanager
async def lifespan(app: FastAPI):
    assert_startup_config()
    # A failed migration aborts startup loudly instead of serving a broken
    # schema. The container exits and the orchestrator reports it.
    try:
        await run_in_threadpool(migrations_runner.upgrade_to_head)
    except Exception:
        logger.exception("Database migration failed, aborting startup")
        raise
    async with async_session() as session:
        await settings_store.assert_startup_state(session)
    logger.info("Tildeck server %s started", get_app_version())
    yield


def create_app() -> FastAPI:
    app = FastAPI(
        title="Tildeck",
        version=get_app_version(),
        lifespan=lifespan,
        docs_url=None,
        redoc_url=None,
        openapi_url="/api/openapi.json",
    )
    app.include_router(health.router)
    # Last: the panel's catch-all route must not shadow any API route.
    panel.mount(app, get_settings().PANEL_DIR)
    return app


app = create_app()
