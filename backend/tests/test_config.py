import pytest

from app.config import Settings


@pytest.mark.parametrize("raw", [
    "postgres://u:p@h:5432/db",
    "postgresql://u:p@h:5432/db",
    "postgresql+asyncpg://u:p@h:5432/db",
])
def test_database_url_gets_asyncpg_driver(raw):
    assert Settings(DATABASE_URL=raw).DATABASE_URL == "postgresql+asyncpg://u:p@h:5432/db"
