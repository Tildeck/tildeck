"""Check the development stack's secrets before it starts.

    docker compose -f docker-compose-dev.yml config --format json | python -m app.dev_env_check

scripts/local.sh and scripts/try-pr.sh run this in the server's dependency
image. It reads the configuration that Compose resolved, so a variable
exported in the shell that overrides .env is seen too. It prints only
variable names and problems, never a value, and exits with status 1 when the
stack must not start.
"""

import json
import sys

from sqlalchemy.engine import make_url

from app.config import MIN_KEY_LENGTH, database_url_problem, secret_problem


def problems(config: dict) -> list[str]:
    services = config.get("services") or {}
    if not {"postgres", "server"} <= services.keys():
        return ["the Compose file must define the services postgres and server"]

    def env(service: str, name: str) -> str | None:
        return (services[service].get("environment") or {}).get(name)

    found = []
    password = env("postgres", "POSTGRES_PASSWORD")
    url = env("server", "DATABASE_URL")
    if problem := secret_problem(password):
        found.append(f"POSTGRES_PASSWORD {problem}")
    if problem := database_url_problem(url, password_required=True):
        found.append(f"DATABASE_URL {problem}")
    if not found and make_url(url).password != password:
        found.append("the password in DATABASE_URL does not match POSTGRES_PASSWORD")
    if problem := secret_problem(env("server", "CONFIG_ENCRYPTION_KEY"), min_length=MIN_KEY_LENGTH):
        found.append(f"CONFIG_ENCRYPTION_KEY {problem}")
    return found


def main() -> int:
    try:
        config = json.load(sys.stdin)
    except ValueError:
        found = ["the Compose configuration could not be read"]
    else:
        found = problems(config) if isinstance(config, dict) else ["the Compose configuration could not be read"]
    for problem in found:
        print(problem, file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
