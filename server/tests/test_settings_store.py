import pytest
from sqlalchemy import select

from app import settings_store
from app.models import AuditEntry, Setting


async def test_default_value_when_nothing_is_set(session):
    assert await settings_store.get_value(session, "registration_mode") == "closed"


async def test_stored_value_is_encrypted_at_rest_and_logged(session):
    await settings_store.set_value(session, "smtp_host", "smtp.example.org", actor="admin@test")
    await session.flush()

    row = await session.get(Setting, "smtp_host")
    assert row.value_encrypted != "smtp.example.org"
    assert await settings_store.get_value(session, "smtp_host") == "smtp.example.org"

    entry = (await session.scalars(select(AuditEntry).where(AuditEntry.entity_id == "smtp_host"))).one()
    assert entry.action == "setting_changed"
    assert entry.new_value == "smtp.example.org"


async def test_secret_is_redacted_in_the_log_and_never_listed(session, monkeypatch):
    await settings_store.set_value(session, "smtp_password", "hunter2-secret", actor="admin@test")
    await session.flush()

    entry = (await session.scalars(select(AuditEntry).where(AuditEntry.entity_id == "smtp_password"))).one()
    assert entry.new_value == settings_store.REDACTED

    listed = {item["key"]: item for item in await settings_store.describe_all(session)}
    assert "value" not in listed["smtp_password"]
    assert listed["smtp_password"]["configured"] is True
    assert listed["smtp_password"]["origin"] == "database"

    # Not even an environment value is revealed.
    monkeypatch.setenv("SMTP_PASSWORD", "from-the-environment")
    listed = {item["key"]: item for item in await settings_store.describe_all(session)}
    assert "value" not in listed["smtp_password"]
    assert listed["smtp_password"]["origin"] == "env"
    assert "from-the-environment" not in repr(listed)


async def test_environment_wins_and_locks_the_field(session, monkeypatch):
    await settings_store.set_value(session, "public_url", "https://stored.example.org", actor="admin@test")
    monkeypatch.setenv("PUBLIC_URL", "https://env.example.org")

    assert await settings_store.get_value(session, "public_url") == "https://env.example.org"
    with pytest.raises(settings_store.SettingLocked):
        await settings_store.set_value(session, "public_url", "https://other.example.org", actor="admin@test")

    listed = {item["key"]: item for item in await settings_store.describe_all(session)}
    assert listed["public_url"]["locked"] is True
    assert listed["public_url"]["value"] == "https://env.example.org"


async def test_invalid_values_are_refused(session):
    with pytest.raises(settings_store.InvalidSettingValue):
        await settings_store.set_value(session, "registration_mode", "everyone", actor="admin@test")
    with pytest.raises(settings_store.InvalidSettingValue):
        await settings_store.set_value(session, "smtp_port", "99999", actor="admin@test")
    with pytest.raises(settings_store.InvalidSettingValue):
        await settings_store.set_value(session, "public_url", "not a url", actor="admin@test")
    # Beyond ten years the idle limit is a typo and would overflow dates.
    with pytest.raises(settings_store.InvalidSettingValue):
        await settings_store.set_value(session, "device_idle_days", "3651", actor="admin@test")
    await settings_store.set_value(session, "device_idle_days", "3650", actor="admin@test")


async def test_unknown_setting(session):
    with pytest.raises(settings_store.UnknownSetting):
        await settings_store.get_value(session, "no_such_setting")


async def test_every_setting_can_be_overridden_from_the_environment():
    assert all(spec.env_var for spec in settings_store.REGISTRY.values())
