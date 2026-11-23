"""Application configuration from environment variables."""

from functools import lru_cache

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    DATABASE_URL: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/ridesync"
    RIDE_TTL_HOURS: int = 12
    CORS_ORIGINS: str = "*"

    @field_validator("DATABASE_URL")
    @classmethod
    def _asyncpg_scheme(cls, v: str) -> str:
        """Hosts like Railway/Heroku hand out postgres:// or postgresql:// URLs;
        async SQLAlchemy needs the asyncpg driver in the scheme."""
        for prefix in ("postgres://", "postgresql://"):
            if v.startswith(prefix):
                return "postgresql+asyncpg://" + v[len(prefix):]
        return v

    @property
    def cors_origin_list(self) -> list[str]:
        if self.CORS_ORIGINS.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.CORS_ORIGINS.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
