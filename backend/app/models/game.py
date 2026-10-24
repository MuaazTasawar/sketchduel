import re
from enum import Enum
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, Field, field_validator

from app.core.config import settings


class GameStatus(str, Enum):
    WAITING = "waiting"
    ACTIVE = "active"
    FINISHED = "finished"


# ----------------------------------------------------------------------------------------------
# Requests
# ----------------------------------------------------------------------------------------------
class JoinRoomRequest(BaseModel):
    room_code: str = Field(min_length=4, max_length=12)

    @field_validator("room_code", mode="before")
    @classmethod
    def normalise_code(cls, value):
        return value.strip().upper() if isinstance(value, str) else value

    @field_validator("room_code")
    @classmethod
    def only_letters_and_digits(cls, value: str) -> str:
        if not re.fullmatch(r"[A-Z0-9]+", value):
            raise ValueError("Room codes contain only letters and digits")
        return value


class DrawingSubmission(BaseModel):
    """A drawing for a game. The player, prompt and elapsed time are NOT sent by the client:
    they come from the verified token and the server's own record of the match."""

    game_id: UUID
    drawing_data: str = Field(min_length=1, max_length=settings.MAX_DRAWING_BYTES)  # base64 PNG


# ----------------------------------------------------------------------------------------------
# Responses
# ----------------------------------------------------------------------------------------------
class CreateRoomResponse(BaseModel):
    room_code: str
    game_id: str
    prompt: str


class GameRoomResponse(BaseModel):
    id: str
    room_code: str
    prompt: str
    status: GameStatus
    player1_id: Optional[str] = None
    player2_id: Optional[str] = None
    # The opponent's score stays hidden (null) until the game is finished.
    player1_score: Optional[float] = None
    player2_score: Optional[float] = None
    winner_id: Optional[str] = None
    is_draw: bool = False
    is_player1: bool = False
    # Server clock: seconds left to draw (null unless the game is active).
    seconds_remaining: Optional[float] = None
    time_limit_seconds: int
    started_at: Optional[str] = None
    finished_at: Optional[str] = None
    created_at: Optional[str] = None


class ScoreResponse(BaseModel):
    # False when this player had already submitted earlier (nothing was re-scored).
    submitted: bool = True
    score: Optional[float] = None
    base_score: Optional[float] = None
    speed_bonus: Optional[float] = None
    bluff_bonus: Optional[float] = None
    bluff_detected: Optional[bool] = None
    recognized_as: Optional[str] = None
    confidence: Optional[float] = None
    prompt_confidence: Optional[float] = None
    blank: Optional[bool] = None
    late: bool = False
    time_taken: Optional[float] = None
    model: Optional[str] = None
    status: GameStatus
    winner_id: Optional[str] = None
    is_draw: bool = False
    room: GameRoomResponse


class PredictResponse(BaseModel):
    recognized_as: str
    confidence: float
    prompt_confidence: float
    bluff_detected: bool
    bluff_eligible: bool
    blank: bool
    model: str
    seconds_remaining: Optional[float] = None


class HistoryItem(BaseModel):
    game_id: str
    room_code: str
    prompt: str
    result: str  # "win" | "loss" | "draw"
    your_score: Optional[float] = None
    opponent_score: Optional[float] = None
    opponent_username: Optional[str] = None
    finished_at: Optional[str] = None


class LeaderboardEntry(BaseModel):
    rank: int
    username: str
    total_wins: int
    total_games: int
    win_rate: float
    best_score: float