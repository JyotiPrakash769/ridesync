"""rides.ended_at (data retention, ride summary)

Revision ID: 0003
Revises: 0002
Create Date: 2026-11-24
"""
from typing import Sequence, Union

import sqlalchemy as sa

from alembic import op

revision: str = "0003"
down_revision: Union[str, None] = "0002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("rides", sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True))
    # Rides already ended before this column existed: treat their expiry as the end.
    op.execute("UPDATE rides SET ended_at = expires_at WHERE status = 'ended'")


def downgrade() -> None:
    op.drop_column("rides", "ended_at")
