"""rides.plan (trip planner: origin, destination, stops, route)

Revision ID: 0005
Revises: 0004
Create Date: 2026-11-24
"""
from typing import Sequence, Union

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "0005"
down_revision: Union[str, None] = "0004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("rides", sa.Column("plan", postgresql.JSONB(), nullable=True))


def downgrade() -> None:
    op.drop_column("rides", "plan")
