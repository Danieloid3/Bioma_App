from functools import lru_cache
from typing import Literal

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str
    jwt_secret: str = Field(min_length=32)
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 15
    refresh_token_days: int = 14
    embedding_worker_poll_seconds: float = Field(default=5, ge=1, le=300)
    redis_url: str = "redis://redis:6379/0"
    rate_limit_window_seconds: int = Field(default=60, ge=1, le=3600)
    rate_limit_login_ip: int = Field(default=20, ge=1, le=1000)
    rate_limit_login_account: int = Field(default=10, ge=1, le=1000)
    rate_limit_copilot: int = Field(default=30, ge=1, le=1000)
    refresh_cookie_name: str = "bioma_refresh_token"
    refresh_cookie_secure: bool = False
    refresh_cookie_samesite: Literal["lax", "strict", "none"] = "lax"
    app_environment: Literal["development", "test", "production"] = "development"
    openai_api_key: str | None = None
    bio_llm_provider: str = "openai"
    bio_llm_model: str = ""
    bio_embedding_model: str = ""
    frontend_origin: str = "http://localhost:5174"

    @model_validator(mode="after")
    def validate_cookie_security(self) -> "Settings":
        if self.app_environment == "production" and not self.refresh_cookie_secure:
            raise ValueError("REFRESH_COOKIE_SECURE must be true in production")
        if self.refresh_cookie_samesite == "none" and not self.refresh_cookie_secure:
            raise ValueError("REFRESH_COOKIE_SECURE is required when SameSite is none")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
