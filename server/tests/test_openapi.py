from pathlib import Path

from app.openapi_export import render

COMMITTED = Path(__file__).resolve().parents[1] / "openapi.json"


def test_committed_contract_matches_the_server():
    assert COMMITTED.read_text(encoding="utf-8") == render(), (
        "server/openapi.json is out of date. Regenerate it and the app's API client: "
        "scripts/verify.sh --area contract prints the exact commands."
    )
