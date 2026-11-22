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

from app.config import MIN_KEY_LENGTH, database_url_problem, secret_problem
from app.protocol import PROTOCOL_VERSION


def contract() -> dict:
    # Building the app needs the bootstrap values but never connects to
    # anything or encrypts, so an export runs without a database. The values
    # have no defaults: scripts/local.sh contract and scripts/verify.sh
    # --area contract pass one-time values.
    problems = []
    if problem := database_url_problem(os.environ.get("DATABASE_URL"), password_required=False):
        problems.append(f"DATABASE_URL {problem}")
    if problem := secret_problem(os.environ.get("CONFIG_ENCRYPTION_KEY"), min_length=MIN_KEY_LENGTH):
        problems.append(f"CONFIG_ENCRYPTION_KEY {problem}")
    if problems:
        raise SystemExit(
            "Refusing to export the API contract: " + "; ".join(problems) + ". scripts/local.sh contract sets both."
        )
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
