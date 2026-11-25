"""riders.battery, rides.sweep_rider_id (leader assist)

Revision ID: 0006
Revises: 0005
Create Date: 2026-11-25
"""
from typing import Sequence, Union

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0006"
down_revision: Union[str, None] = "0005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("riders", sa.Column("battery", sa.SmallInteger(), nullable=True))
    op.add_column("rides", sa.Column("sweep_rider_id", postgresql.UUID(as_uuid=True), nullable=True))
    op.create_foreign_key(
        "fk_sweep", "rides", "riders", ["sweep_rider_id"], ["id"], ondelete="SET NULL"
    )


def downgrade() -> None:
    op.drop_constraint("fk_sweep", "rides", type_="foreignkey")
    op.drop_column("rides", "sweep_rider_id")
    op.drop_column("riders", "battery")
