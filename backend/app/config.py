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
    # Ended rides (riders, locations, events) are deleted after this many days.
    RETENTION_DAYS: int = 7
    # Public URL of this backend, used for QR join links (https://host/join/CODE).
    # Empty = the original https://ridesync.app/join/CODE.
    PUBLIC_BASE_URL: str = ""
    # Where the join page sends people who don't have the app yet.
    APP_DOWNLOAD_URL: str = "https://github.com/JyotiPrakash769/ridesync/releases/latest"
    # Comma-separated SHA-256 fingerprints of the APK signing cert(s); enables
    # /.well-known/assetlinks.json so join links open the app directly.
    ANDROID_CERT_SHA256: str = ""
    # Google Maps Platform server key (Routes API + Places API (New)). Stays on
    # the server; the app never sees it. Empty = OSM place search + straight-
    # line "approximate" routes.
    GOOGLE_MAPS_SERVER_KEY: str = ""
    # Contact for the OpenStreetMap Nominatim fallback (their usage policy).
    NOMINATIM_USER_AGENT: str = "RideSync/0.3 (+https://github.com/JyotiPrakash769/ridesync)"
    # Optional error reporting (https://sentry.io). Empty = disabled.
    SENTRY_DSN: str = ""
    # Comma-separated browser origins allowed to call the API. Empty = no CORS
    # (the Android app does not need it). Use "*" only for local experiments.
    CORS_ORIGINS: str = ""

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
        if not self.CORS_ORIGINS.strip():
            return []
        if self.CORS_ORIGINS.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.CORS_ORIGINS.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
