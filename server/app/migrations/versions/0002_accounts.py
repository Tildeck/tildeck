"""Accounts, devices, and one-time email links.

Revision ID: 0002
Revises: 0001
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0002"
down_revision: Union[str, None] = "0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "accounts",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("email", sa.String(length=320), nullable=False, unique=True),
        sa.Column("email_verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("disabled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("locale", sa.String(length=8), nullable=False),
        sa.Column("vault_id", sa.String(length=36), nullable=False),
        sa.Column("kdf_ops", sa.Integer(), nullable=False),
        sa.Column("kdf_mem", sa.Integer(), nullable=False),
        sa.Column("kdf_salt", sa.String(length=64), nullable=False),
        sa.Column("auth_key_hash", sa.Text(), nullable=False),
        sa.Column("recovery_auth_hash", sa.Text(), nullable=False),
        sa.Column("wrap_pw", sa.Text(), nullable=False),
        sa.Column("wrap_rk", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_table(
        "devices",
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("account_id", sa.String(length=36), sa.ForeignKey("accounts.id", ondelete="CASCADE"), nullable=False),
        sa.Column("name", sa.String(length=100), nullable=False),
        sa.Column("status", sa.String(length=10), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=True, unique=True),
        sa.Column("claim_token_hash", sa.String(length=64), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("approved_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_devices_account", "devices", ["account_id"])
    op.create_table(
        "email_tokens",
        sa.Column("token_hash", sa.String(length=64), primary_key=True),
        sa.Column("purpose", sa.String(length=10), nullable=False),
        sa.Column("account_id", sa.String(length=36), sa.ForeignKey("accounts.id", ondelete="CASCADE"), nullable=False),
        sa.Column("device_id", sa.String(length=36), sa.ForeignKey("devices.id", ondelete="CASCADE"), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_table("email_tokens")
    op.drop_index("ix_devices_account", table_name="devices")
    op.drop_table("devices")
    op.drop_table("accounts")
