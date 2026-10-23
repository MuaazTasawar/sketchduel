from datetime import datetime
from typing import Optional

from pydantic import BaseModel, EmailStr, Field, field_validator


class UserRegister(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6, max_length=72)
    username: str = Field(min_length=3, max_length=20, pattern=r"^[A-Za-z0-9_]+$")

    @field_validator("username", mode="before")
    @classmethod
    def strip_username(cls, value):
        return value.strip() if isinstance(value, str) else value


class UserLogin(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=72)


class UserResponse(BaseModel):
    """A user's own profile (includes e-mail)."""

    id: str
    email: str
    username: str
    total_wins: int = 0
    total_games: int = 0
    best_score: float = 0.0
    created_at: Optional[datetime] = None


class PublicProfile(BaseModel):
    """What other players may see. Never includes the e-mail address."""

    id: str
    username: str
    total_wins: int = 0
    total_games: int = 0
    best_score: float = 0.0


class RegisterResponse(BaseModel):
    message: str
    user_id: str
    email_confirmation_required: bool


class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: dict