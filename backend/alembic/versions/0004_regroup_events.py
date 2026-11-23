"""regroup point on rides + ride_events log (summary)

Revision ID: 0004
Revises: 0003
Create Date: 2026-11-24
"""
from typing import Sequence, Union

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0004"
down_revision: Union[str, None] = "0003"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("rides", sa.Column("regroup_lat", sa.Float(), nullable=True))
    op.add_column("rides", sa.Column("regroup_lng", sa.Float(), nullable=True))
    op.add_column("rides", sa.Column("regroup_label", sa.String(40), nullable=True))
    op.add_column("rides", sa.Column("regroup_set_at", sa.DateTime(timezone=True), nullable=True))
    op.create_table(
        "ride_events",
        sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column(
            "ride_id", sa.CHAR(6), sa.ForeignKey("rides.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "rider_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("riders.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("type", sa.String(24), nullable=False),
        sa.Column("distance_m", sa.Integer(), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
    )
    op.create_index("idx_ride_events_ride", "ride_events", ["ride_id", "created_at"])


def downgrade() -> None:
    op.drop_index("idx_ride_events_ride", table_name="ride_events")
    op.drop_table("ride_events")
    for c in ("regroup_set_at", "regroup_label", "regroup_lng", "regroup_lat"):
        op.drop_column("rides", c)
