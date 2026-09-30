"""Encrypted vault records and the per-account revision counter.

Revision ID: 0003
Revises: 0002
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0003"
down_revision: Union[str, None] = "0002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("accounts", sa.Column("revision", sa.BigInteger(), nullable=False, server_default="0"))
    op.create_table(
        "records",
        sa.Column(
            "account_id", sa.String(length=36), sa.ForeignKey("accounts.id", ondelete="CASCADE"), primary_key=True
        ),
        sa.Column("id", sa.String(length=36), primary_key=True),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.Column("revision", sa.BigInteger(), nullable=False),
        sa.Column("deleted", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("nonce", sa.String(length=64), nullable=True),
        sa.Column("ct", sa.Text(), nullable=True),
        sa.Column("device_id", sa.String(length=36), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
    )
    op.create_index("ix_records_account_revision", "records", ["account_id", "revision"])


def downgrade() -> None:
    op.drop_index("ix_records_account_revision", table_name="records")
    op.drop_table("records")
    op.drop_column("accounts", "revision")
