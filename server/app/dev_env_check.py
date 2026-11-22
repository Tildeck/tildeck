"""Check the development stack's secrets before it starts.

    docker compose -f docker-compose-dev.yml config --format json | python -m app.dev_env_check

scripts/local.sh and scripts/try-pr.sh run this in the server's dependency
image. It reads the configuration that Compose resolved, so a variable
exported in the shell that overrides .env is seen too. It prints only
variable names and problems, never a value. Exit status 1: a value must be
replaced; 2: the configuration could not be read.
"""

import json
import sys

from sqlalchemy.engine import make_url

from app.config import MIN_KEY_LENGTH, database_url_problem, generated_value_problem, variant_spellings

CHECKED = {"postgres": ("POSTGRES_PASSWORD",), "server": ("DATABASE_URL", "CONFIG_ENCRYPTION_KEY")}


def problems(config: dict) -> list[str]:
    services = config.get("services") or {}
    if not set(CHECKED) <= services.keys():
        return ["the Compose file must define the services postgres and server"]

    environments = {name: services[name].get("environment") or {} for name in CHECKED}
    found = []
    # The server reads its settings case-insensitively; another spelling of a
    # checked name could replace the value checked here.
    for service, names in CHECKED.items():
        for name in names:
            if variant_spellings(environments[service], name):
                found.append(f"{name} is also set under another spelling")

    db_value = environments["postgres"].get("POSTGRES_PASSWORD")
    url = environments["server"].get("DATABASE_URL")
    if problem := generated_value_problem(db_value):
        found.append(f"POSTGRES_PASSWORD {problem}")
    if problem := database_url_problem(url, password_required=True):
        found.append(f"DATABASE_URL {problem}")
    if not found and make_url(url).password != db_value:
        found.append("the password in DATABASE_URL does not match POSTGRES_PASSWORD")
    settings_value = environments["server"].get("CONFIG_ENCRYPTION_KEY")
    if problem := generated_value_problem(settings_value, min_length=MIN_KEY_LENGTH):
        found.append(f"CONFIG_ENCRYPTION_KEY {problem}")
    return found


def main() -> int:
    try:
        config = json.load(sys.stdin)
    except ValueError:
        config = None
    services = config.get("services") if isinstance(config, dict) else None
    if not isinstance(services, dict) or not set(CHECKED) <= services.keys():
        print("the Compose configuration could not be read, or lacks the services postgres and server", file=sys.stderr)
        return 2
    found = problems(config)
    for problem in found:
        print(problem, file=sys.stderr)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
