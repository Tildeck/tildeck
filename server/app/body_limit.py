"""A cap on request bodies, enforced before anything reads them: a client
that is not signed in must not make the server buffer an unbounded body.

Sync pushes carry records (the client splits a push to stay below the cap);
every other request is small.
"""

from starlette.exceptions import HTTPException
from starlette.types import ASGIApp, Message, Receive, Scope, Send

SYNC_PREFIX = "/api/sync/"
SYNC_LIMIT = 16 * 1024 * 1024
DEFAULT_LIMIT = 1024 * 1024

_REFUSAL = b'{"error":"invalid_request"}'


class RequestTooLarge(HTTPException):
    """Raised while the body is read, once it passes the cap."""

    def __init__(self) -> None:
        super().__init__(413)


def limit_for(path: str) -> int:
    return SYNC_LIMIT if path.startswith(SYNC_PREFIX) else DEFAULT_LIMIT


class BodyLimitMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        limit = limit_for(scope["path"])
        # A declared length over the cap is refused without reading a byte.
        for name, value in scope["headers"]:
            if name == b"content-length" and (not value.isdigit() or int(value) > limit):
                await _refuse(send)
                return
        # Without a declared length (chunked), the bytes are counted as
        # they arrive.
        received = 0

        async def counted() -> Message:
            nonlocal received
            message = await receive()
            if message["type"] == "http.request":
                received += len(message.get("body", b""))
                if received > limit:
                    raise RequestTooLarge()
            return message

        await self.app(scope, counted, send)


async def _refuse(send: Send) -> None:
    await send(
        {
            "type": "http.response.start",
            "status": 413,
            "headers": [(b"content-type", b"application/json"), (b"content-length", str(len(_REFUSAL)).encode())],
        }
    )
    await send({"type": "http.response.body", "body": _REFUSAL})
