"""SQLAlchemy declarative base.

Models live in app.models; import that package (not this module) to register
every table on Base.metadata (Alembic's env.py does this).
"""

from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass
