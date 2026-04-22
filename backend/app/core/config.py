"""
Application configuration — reads from environment variables with sensible defaults.
"""

import os
from enum import Enum
from functools import lru_cache
from urllib.parse import quote_plus

from pydantic_settings import BaseSettings


class Environment(str, Enum):
    DEVELOPMENT = "development"
    STAGING = "staging"
    PRODUCTION = "production"


class Settings(BaseSettings):
    # --- Environment ---
    ENVIRONMENT: Environment = Environment.DEVELOPMENT
    DEBUG: bool = True

    # --- API ---
    API_V1_PREFIX: str = "/v1"
    PROJECT_NAME: str = "WoundOS Backend"
    CORS_ORIGINS: list[str] = ["*"]

    # --- Database (Cloud SQL / local PostgreSQL) ---
    DB_HOST: str = "localhost"
    DB_PORT: int = 5432
    DB_USER: str = "woundos"
    DB_PASSWORD: str = "woundos_dev"
    DB_NAME: str = "woundos"
    # For Cloud SQL socket connections (production):
    DB_SOCKET_DIR: str = "/cloudsql"
    DB_INSTANCE_CONNECTION_NAME: str = ""

    def _url(self, driver: str) -> str:
        """Build a SQLAlchemy database URL, URL-encoding credentials.

        `openssl rand -base64` passwords routinely contain '/', '+', '=' —
        all URL-reserved — so percent-encode user+password before interpolation.
        """
        user = quote_plus(self.DB_USER)
        pw = quote_plus(self.DB_PASSWORD)
        if self.DB_INSTANCE_CONNECTION_NAME:
            # Cloud SQL Unix socket (Cloud Run with --add-cloudsql-instances)
            return (
                f"{driver}://{user}:{pw}"
                f"@/{self.DB_NAME}"
                f"?host={self.DB_SOCKET_DIR}/{self.DB_INSTANCE_CONNECTION_NAME}"
            )
        # Direct TCP connection (local dev / VPC)
        return f"{driver}://{user}:{pw}@{self.DB_HOST}:{self.DB_PORT}/{self.DB_NAME}"

    @property
    def database_url(self) -> str:
        return self._url("postgresql+asyncpg")

    @property
    def database_url_sync(self) -> str:
        """Sync URL for Alembic migrations."""
        return self._url("postgresql")

    # --- Google Cloud Storage ---
    GCS_BUCKET: str = "woundos-scans-dev"
    GCS_PROJECT_ID: str = ""

    # --- Google Pub/Sub ---
    PUBSUB_PROJECT_ID: str = ""
    PUBSUB_TOPIC_SCAN_READY: str = "scan-ready"

    # --- Firebase Auth ---
    FIREBASE_PROJECT_ID: str = ""

    # --- Anthropic (Claude Haiku) ---
    ANTHROPIC_API_KEY: str = ""

    # --- JWT Signing ---
    JWT_SECRET_KEY: str = "change-me-in-production"
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRATION_SECONDS: int = 3600

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = True


@lru_cache
def get_settings() -> Settings:
    return Settings()
