"""Liveness, readiness, and the server identity a client checks first.

Liveness answers as long as the process serves requests. Readiness also
requires the database, and answers 503 with a stable error code when it is
unreachable, so the container health check and any proxy stop routing to it.
"""

import logging
from typing import Literal

from fastapi import APIRouter
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from sqlalchemy import text

from app import db
from app.config import get_app_version
from app.protocol import PROTOCOL_VERSION, ErrorCode

router = APIRouter(prefix="/api", tags=["health"])
logger = logging.getLogger("tildeck.health")


class Liveness(BaseModel):
    status: Literal["ok"]


class Readiness(BaseModel):
    status: Literal["ok", "error"]
    database: Literal["ok", "error"]
    error: ErrorCode | None = None


class ServerInfo(BaseModel):
    name: Literal["tildeck"]
    version: str
    protocol_version: int


@router.get("/health/live", response_model=Liveness, operation_id="getLiveness")
async def live() -> Liveness:
    return Liveness(status="ok")


@router.get(
    "/health/ready",
    response_model=Readiness,
    operation_id="getReadiness",
    responses={503: {"model": Readiness, "description": "The database is unreachable"}},
)
async def ready() -> JSONResponse:
    try:
        async with db.engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
    except Exception as exc:  # noqa: BLE001 - any failure means not ready
        logger.error("Readiness: database unreachable: %s", exc)
        body = Readiness(status="error", database="error", error=ErrorCode.database_unavailable)
        return JSONResponse(body.model_dump(mode="json"), status_code=503)
    return JSONResponse(Readiness(status="ok", database="ok").model_dump(mode="json"))


@router.get("/info", response_model=ServerInfo, operation_id="getServerInfo")
async def info() -> ServerInfo:
    return ServerInfo(name="tildeck", version=get_app_version(), protocol_version=PROTOCOL_VERSION)
