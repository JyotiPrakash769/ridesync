"""rider secret tokens (security)

Revision ID: 0002
Revises: 0001
Create Date: 2026-11-24
"""
from typing import Sequence, Union

import sqlalchemy as sa

from alembic import op

revision: str = "0002"
down_revision: Union[str, None] = "0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # SHA-256 hex of the rider's secret token. Rows from v0.1 stay NULL and
    # can no longer authenticate (those riders simply re-join).
    op.add_column("riders", sa.Column("token_hash", sa.String(64), nullable=True))


def downgrade() -> None:
    op.drop_column("riders", "token_hash")
