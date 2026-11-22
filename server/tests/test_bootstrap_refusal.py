"""The tests, the contract export, and the development stack check refuse
missing, placeholder, and once-published values instead of falling back to
a default, and never print the value they refuse."""

import io
import json
import os
import secrets
import subprocess
import sys
from pathlib import Path

import pytest

from app import dev_env_check
from app.config import RETIRED_VALUES

SERVER = Path(__file__).resolve().parents[1]
VARIABLES = (
    "TEST_DATABASE_URL",
    "TEST_CONFIG_ENCRYPTION_KEY",
    "DATABASE_URL",
    "CONFIG_ENCRYPTION_KEY",
)


def url(password: str, database: str = "tildeck_test") -> str:
    # Built from parts: no URL with a password is written out in this file.
    return "postgresql+asyncpg://tildeck:" + password + "@db:5432/" + database


def run(module_args: list[str], **env: str) -> subprocess.CompletedProcess:
    clean = {k: v for k, v in os.environ.items() if k not in VARIABLES}
    clean["PYTHONPATH"] = str(SERVER)
    return subprocess.run(
        [sys.executable, *module_args], cwd=SERVER, env={**clean, **env}, capture_output=True, text=True, timeout=60
    )


def run_conftest(**env: str) -> subprocess.CompletedProcess:
    return run(["-c", "import runpy; runpy.run_path('tests/conftest.py')"], **env)


def run_export(**env: str) -> subprocess.CompletedProcess:
    return run(["-m", "app.openapi_export"], **env)


DUMMY = secrets.token_hex(16)
KEY = secrets.token_hex(32)
# Each value once published in this repository, for the refusal cases.
RETIRED = sorted(RETIRED_VALUES)


def good_tests_env() -> dict[str, str]:
    return {"TEST_DATABASE_URL": url(DUMMY), "TEST_CONFIG_ENCRYPTION_KEY": KEY}


def test_tests_start_with_generated_values():
    result = run_conftest(**good_tests_env())
    assert result.returncode == 0, result.stderr[-2000:]


@pytest.mark.parametrize("variable", ["TEST_DATABASE_URL", "TEST_CONFIG_ENCRYPTION_KEY"])
@pytest.mark.parametrize("value", [None, "", "   "])
def test_tests_refuse_a_missing_value(variable, value):
    env = good_tests_env()
    if value is None:
        del env[variable]
    else:
        env[variable] = value
    result = run_conftest(**env)
    assert result.returncode != 0
    assert f"{variable} is not set" in result.stderr


@pytest.mark.parametrize(
    "value",
    [
        url("change-me"),
        url("tildeck"),
        url(DUMMY, "tildeck"),
        url(DUMMY, "other#x_test"),
        url(DUMMY, "other?database=x_test"),
        url(DUMMY + "%40x"),
        url(DUMMY + "/x"),
        url(DUMMY + ":5432"),
        url(DUMMY + "@x"),
        "postgresql+asyncpg://tildeck@db:5432/tildeck_test",
        url(DUMMY).replace(":5432/", ":0/"),
        url(DUMMY).replace(":5432/", ":99999/"),
        url(DUMMY).replace("postgresql+asyncpg:", "postgresql:"),
    ],
    ids=[
        "placeholder-password",
        "published-password",
        "not-a-test-database",
        "fragment",
        "query",
        "percent-encoding",
        "slash-in-password",
        "colon-in-password",
        "second-at",
        "no-password",
        "port-zero",
        "port-too-high",
        "other-driver",
    ],
)
def test_tests_refuse_a_bad_database_url(value):
    result = run_conftest(**{**good_tests_env(), "TEST_DATABASE_URL": value})
    assert result.returncode != 0
    assert "TEST_DATABASE_URL" in result.stderr
    assert DUMMY not in result.stdout + result.stderr


def test_tests_drop_other_spellings_of_the_settings():
    # Settings reads names case-insensitively: a leftover database_url must
    # not compete with the test database.
    result = run(
        [
            "-c",
            "import os, runpy; runpy.run_path('tests/conftest.py');"
            "print(sorted(k for k in os.environ if k.lower() in ('database_url', 'config_encryption_key')))",
        ],
        **good_tests_env(),
        database_url=url(DUMMY, "other"),
        Config_Encryption_Key="change-me",
    )
    assert result.returncode == 0, result.stderr[-2000:]
    names = result.stdout.strip().splitlines()[-1]
    assert names == str(sorted(["DATABASE_URL", "CONFIG_ENCRYPTION_KEY"]))


@pytest.mark.parametrize(
    "value",
    ["change-me", *(f"  {value}  " for value in RETIRED), KEY[:31]],
    ids=["placeholder", *(f"published-{i}-with-spaces" for i in range(len(RETIRED))), "short"],
)
def test_tests_refuse_a_bad_key(value):
    result = run_conftest(**{**good_tests_env(), "TEST_CONFIG_ENCRYPTION_KEY": value})
    assert result.returncode != 0
    assert "TEST_CONFIG_ENCRYPTION_KEY" in result.stderr


EXPORT_URL = "postgresql+asyncpg://export@localhost:5432/export"


def test_export_runs_with_generated_values():
    result = run_export(DATABASE_URL=EXPORT_URL, CONFIG_ENCRYPTION_KEY=KEY)
    assert result.returncode == 0, result.stderr[-2000:]
    assert json.loads(result.stdout)["info"]["title"] == "Tildeck"


@pytest.mark.parametrize(
    ("variable", "value", "problem"),
    [
        ("DATABASE_URL", None, "is not set"),
        ("DATABASE_URL", " ", "is not set"),
        ("DATABASE_URL", "postgresql+asyncpg://export:change-me@localhost:5432/export", "password is a placeholder"),
        ("DATABASE_URL", url(DUMMY, "export?password=x"), "must have the generated form"),
        ("CONFIG_ENCRYPTION_KEY", None, "is not set"),
        ("CONFIG_ENCRYPTION_KEY", "", "is not set"),
        ("CONFIG_ENCRYPTION_KEY", "change-me", "is a placeholder"),
        *(("CONFIG_ENCRYPTION_KEY", value, "is a value once published") for value in RETIRED),
        ("CONFIG_ENCRYPTION_KEY", KEY[:31], "is too short"),
    ],
)
def test_export_refuses_a_bad_value(variable, value, problem):
    env = {"DATABASE_URL": EXPORT_URL, "CONFIG_ENCRYPTION_KEY": KEY}
    if value is None:
        del env[variable]
    else:
        env[variable] = value
    result = run_export(**env)
    assert result.returncode != 0
    assert f"{variable} {problem}" in result.stderr
    assert result.stdout == ""
    assert DUMMY not in result.stderr


def test_export_refuses_another_spelling():
    result = run_export(DATABASE_URL=EXPORT_URL, CONFIG_ENCRYPTION_KEY=KEY, config_encryption_key="change-me")
    assert result.returncode != 0
    assert "CONFIG_ENCRYPTION_KEY is also set under another spelling" in result.stderr


def compose_config(password: str = DUMMY, database_url: str | None = None, key: str = KEY) -> dict:
    return {
        "services": {
            "postgres": {"environment": {"POSTGRES_PASSWORD": password}},
            "server": {
                "environment": {
                    "DATABASE_URL": url(DUMMY) if database_url is None else database_url,
                    "CONFIG_ENCRYPTION_KEY": key,
                }
            },
        }
    }


def with_another_spelling() -> dict:
    config = compose_config()
    config["services"]["server"]["environment"]["config_encryption_key"] = "change-me"
    return config


def test_dev_stack_with_generated_values_passes():
    assert dev_env_check.problems(compose_config()) == []


@pytest.mark.parametrize(
    ("config", "expected"),
    [
        (compose_config(password="change-me", database_url=url("change-me")), "POSTGRES_PASSWORD is a placeholder"),
        (compose_config(password="tildeck", database_url=url("tildeck")), "POSTGRES_PASSWORD is a value once"),
        (compose_config(password=DUMMY + "x"), "does not match POSTGRES_PASSWORD"),
        (compose_config(database_url=url(DUMMY, "tildeck?password=x")), "DATABASE_URL must have the generated form"),
        (compose_config(key="change-me"), "CONFIG_ENCRYPTION_KEY is a placeholder"),
        (compose_config(key=KEY[:31]), "CONFIG_ENCRYPTION_KEY is too short"),
        ({"services": {"server": {}}}, "must define the services postgres and server"),
        (with_another_spelling(), "CONFIG_ENCRYPTION_KEY is also set under another spelling"),
    ],
    ids=[
        "placeholder",
        "published",
        "mismatch",
        "query",
        "placeholder-key",
        "short-key",
        "missing-service",
        "spelling",
    ],
)
def test_dev_stack_refuses_bad_values(config, expected):
    found = dev_env_check.problems(config)
    assert any(expected in problem for problem in found), found


@pytest.mark.parametrize(
    ("stdin", "status"),
    [
        (json.dumps(compose_config(password="change-me")), dev_env_check.VALUES_TO_REPLACE),
        ("not json " + DUMMY, 2),
        (json.dumps({"services": {"server": {"environment": {"DATABASE_URL": url(DUMMY)}}}}), 2),
    ],
    ids=["value-to-replace", "unreadable", "missing-service"],
)
def test_dev_stack_check_never_prints_a_value(stdin, status, monkeypatch, capsys):
    # 3 asks for new values; 2 means the check could not judge them.
    monkeypatch.setattr(sys, "stdin", io.StringIO(stdin))
    assert dev_env_check.main() == status
    out, err = capsys.readouterr()
    assert DUMMY not in out + err
    assert KEY not in out + err
