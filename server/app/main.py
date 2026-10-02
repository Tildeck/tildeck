"""Application entry point: uvicorn app.main:app."""

import logging
import re
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware

from app import admins, migrations_runner, panel, settings_store
from app.body_limit import BodyLimitMiddleware, RequestTooLarge
from app.config import get_app_version, get_settings
from app.db import async_session
from app.mailer import SmtpMailer
from app.protocol import ApiError, ErrorCode
from app.routers import account, admin, health, links, sync

# Uvicorn configures only its own loggers. Without this every app log line
# below WARNING is dropped.
logging.basicConfig(level=logging.INFO, format="%(levelname)s:     %(name)s - %(message)s")
logger = logging.getLogger("tildeck")

_LINK_TOKEN = re.compile(r"(/links/[a-z]+/)[^/?\s]+")


class _HideLinkTokens(logging.Filter):
    """The access log line carries the path, and the path of an email link
    is its secret: the token is replaced before the line is written."""

    def filter(self, record: logging.LogRecord) -> bool:
        args = record.args
        if isinstance(args, tuple) and len(args) >= 3 and isinstance(args[2], str):
            record.args = (*args[:2], _LINK_TOKEN.sub(r"\1***", args[2]), *args[3:])
        return True


logging.getLogger("uvicorn.access").addFilter(_HideLinkTokens())


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
        await admins.ensure_setup_token(session)
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
    # Outgoing email; tests replace it with an in-memory mailer.
    app.state.mailer = SmtpMailer()

    @app.exception_handler(ApiError)
    async def api_error(request: Request, exc: ApiError) -> JSONResponse:
        return JSONResponse({"error": exc.code.value}, status_code=exc.status_code)

    @app.exception_handler(RequestTooLarge)
    async def too_large(request: Request, exc: RequestTooLarge) -> JSONResponse:
        return JSONResponse({"error": ErrorCode.invalid_request.value}, status_code=413)

    # A malformed request gets the same stable error body as every refusal.
    # The field details stay out of the answer: clients never show them.
    @app.exception_handler(RequestValidationError)
    async def invalid_request(request: Request, exc: RequestValidationError) -> JSONResponse:
        return JSONResponse({"error": ErrorCode.invalid_request.value}, status_code=422)

    def contract() -> dict:
        """FastAPI documents its own validation error body on every route; the
        server answers with the stable error body instead, so the contract
        says so (and the generated client gets one error type)."""
        if app.openapi_schema is None:
            from fastapi.openapi.utils import get_openapi

            schema = get_openapi(title=app.title, version=app.version, routes=app.routes)
            _stable_validation_errors(schema)
            app.openapi_schema = schema
        return app.openapi_schema

    app.openapi = contract

    app.include_router(health.router)
    app.include_router(account.router)
    app.include_router(sync.router)
    app.include_router(links.router)
    app.include_router(admin.router)
    # Last: the panel's catch-all route must not shadow any API route.
    panel.mount(app, get_settings().PANEL_DIR)
    # The client's address, as the trusted proxy saw it: the nearest entry of
    # X-Forwarded-For that is not a trusted proxy, never one the client wrote.
    app.add_middleware(ProxyHeadersMiddleware, trusted_hosts=get_settings().TRUSTED_PROXIES)
    app.add_middleware(BodyLimitMiddleware)
    return app


def _stable_validation_errors(schema: dict) -> None:
    components = schema.get("components", {}).get("schemas", {})
    components.pop("HTTPValidationError", None)
    components.pop("ValidationError", None)
    for path in schema.get("paths", {}).values():
        for operation in path.values():
            response = operation.get("responses", {}).get("422")
            if response is not None:
                response["description"] = "Invalid request"
                response["content"] = {"application/json": {"schema": {"$ref": "#/components/schemas/ErrorBody"}}}


app = create_app()
