"""The client and server contract constants.

The protocol version changes only when a client built for the previous
version can no longer sync correctly. Error codes are stable snake_case
identifiers: clients map them to localized messages, so a code is never
renamed once released.
"""

from enum import StrEnum

from fastapi import Header
from pydantic import BaseModel

PROTOCOL_VERSION = 1
PROTOCOL_HEADER = "Tildeck-Protocol"


class ErrorCode(StrEnum):
    database_unavailable = "database_unavailable"
    unsupported_protocol = "unsupported_protocol"
    # Registration.
    registration_closed = "registration_closed"
    registration_needs_email = "registration_needs_email"
    registration_invite_required = "registration_invite_required"
    email_taken = "email_taken"
    invalid_email = "invalid_email"
    # Sign-in, devices, and tokens.
    invalid_credentials = "invalid_credentials"
    account_disabled = "account_disabled"
    unauthorized = "unauthorized"
    device_pending = "device_pending"
    device_revoked = "device_revoked"
    device_not_found = "device_not_found"
    invalid_token = "invalid_token"
    token_expired = "token_expired"
    recovery_failed = "recovery_failed"
    rate_limited = "rate_limited"
    invalid_request = "invalid_request"
    # Email.
    email_unavailable = "email_unavailable"
    email_not_verified = "email_not_verified"


class ErrorBody(BaseModel):
    error: ErrorCode


class ApiError(Exception):
    """A refusal with a stable error code; rendered as {"error": code}."""

    def __init__(self, status_code: int, code: ErrorCode):
        super().__init__(code.value)
        self.status_code = status_code
        self.code = code


def require_protocol(tildeck_protocol: int | None = Header(default=None, alias=PROTOCOL_HEADER)) -> None:
    """Router dependency for the account, device, and sync APIs. The health
    and identity endpoints stay open to any client, so an old app can still
    learn which version the server speaks."""
    if tildeck_protocol != PROTOCOL_VERSION:
        raise ApiError(400, ErrorCode.unsupported_protocol)


def errors(*codes: tuple[int, str]) -> dict:
    """OpenAPI response entries for refusals with the stable error body."""
    return {status: {"model": ErrorBody, "description": description} for status, description in codes}
