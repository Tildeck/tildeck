"""Print the API contract as stable JSON.

    python -m app.openapi_export > openapi.json

The committed server/openapi.json is the client and server contract. The
server version is left out of the document on purpose: it changes with every
release, while the contract changes only when the API does.
"""

import json
import os
import sys

from fastapi.openapi.utils import get_openapi

from app.protocol import PROTOCOL_VERSION


def contract() -> dict:
    # Building the app needs bootstrap values but never connects to anything,
    # so an export runs anywhere, without a database or a real key.
    os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://export@localhost:5432/export")
    os.environ.setdefault("CONFIG_ENCRYPTION_KEY", "openapi-export-only")
    from app.main import _stable_validation_errors, app

    schema = get_openapi(
        title="Tildeck",
        version=f"protocol-{PROTOCOL_VERSION}",
        description="The Tildeck sync server API.",
        routes=app.routes,
    )
    _stable_validation_errors(schema)
    return schema


def render() -> str:
    return json.dumps(contract(), indent=2, sort_keys=True, ensure_ascii=False) + "\n"


if __name__ == "__main__":
    sys.stdout.write(render())
