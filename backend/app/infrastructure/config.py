from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str
    jwt_secret: str = Field(min_length=32)
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 15
    refresh_token_days: int = 14
    openai_api_key: str | None = None
    bio_llm_provider: str = "openai"
    bio_llm_model: str = ""
    bio_embedding_model: str = ""
    frontend_origin: str = "http://localhost:5174"


@lru_cache
def get_settings() -> Settings:
    return Settings()
