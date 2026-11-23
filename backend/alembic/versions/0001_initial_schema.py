"""initial schema: rides, riders, locations (foundation doc §3)

Revision ID: 0001
Revises:
Create Date: 2026-11-23
"""
from typing import Sequence, Union

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "rides",
        sa.Column("id", sa.CHAR(6), primary_key=True),
        sa.Column("leader_rider_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("status", sa.String(10), nullable=False, server_default=sa.text("'active'")),
        sa.Column("threshold_m", sa.Integer(), nullable=False, server_default=sa.text("500")),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_table(
        "riders",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "ride_id", sa.CHAR(6), sa.ForeignKey("rides.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("display_name", sa.String(50), nullable=False),
        sa.Column("role", sa.String(10), nullable=False, server_default=sa.text("'member'")),
        sa.Column(
            "joined_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_lat", sa.Float(), nullable=True),
        sa.Column("last_lng", sa.Float(), nullable=True),
        sa.Column("last_speed_kph", sa.Float(), nullable=True),
        sa.Column("is_online", sa.Boolean(), nullable=False, server_default=sa.text("true")),
    )
    op.create_foreign_key("fk_leader", "rides", "riders", ["leader_rider_id"], ["id"])
    op.create_table(
        "locations",
        sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=True),
        sa.Column(
            "rider_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("riders.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("lat", sa.Float(), nullable=False),
        sa.Column("lng", sa.Float(), nullable=False),
        sa.Column("recorded_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "received_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
    )
    op.create_index("idx_locations_rider_time", "locations", ["rider_id", "recorded_at"])
    op.create_index("idx_riders_ride", "riders", ["ride_id"])


def downgrade() -> None:
    op.drop_index("idx_riders_ride", table_name="riders")
    op.drop_index("idx_locations_rider_time", table_name="locations")
    op.drop_table("locations")
    op.drop_constraint("fk_leader", "rides", type_="foreignkey")
    op.drop_table("riders")
    op.drop_table("rides")
