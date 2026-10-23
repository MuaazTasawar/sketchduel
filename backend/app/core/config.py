from functools import lru_cache
from pathlib import Path
from typing import List

from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    """Application settings, loaded from environment variables or backend/.env."""

    model_config = SettingsConfigDict(
        env_file=BACKEND_DIR / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Supabase
    SUPABASE_URL: str
    SUPABASE_KEY: str
    SUPABASE_SERVICE_KEY: str

    # Legacy / reserved (kept optional so existing .env files keep working)
    SECRET_KEY: str = ""

    ENVIRONMENT: str = "development"

    # CORS: comma-separated list of origins, e.g. "https://sketchduel.vercel.app"
    ALLOWED_ORIGINS: str = ""

    # ML model (ONNX). Relative paths are resolved against the backend folder.
    MODEL_PATH: str = "models/quickdraw.onnx"

    # Gameplay rules (enforced on the server)
    DRAWING_SECONDS: int = 60
    SUBMIT_GRACE_SECONDS: int = 5

    # Abuse protection
    MAX_DRAWING_BYTES: int = 2_000_000
    RATE_LIMIT_PER_MINUTE: int = 30

    @property
    def is_production(self) -> bool:
        return self.ENVIRONMENT.lower() == "production"

    @property
    def allowed_origins_list(self) -> List[str]:
        return [o.strip() for o in self.ALLOWED_ORIGINS.split(",") if o.strip()]

    @property
    def model_file(self) -> Path:
        path = Path(self.MODEL_PATH)
        return path if path.is_absolute() else BACKEND_DIR / path


@lru_cache()
def get_settings() -> Settings:
    return Settings()


settings = get_settings()