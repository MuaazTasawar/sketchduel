from pydantic import BaseModel
from typing import Optional, List
from enum import Enum
from datetime import datetime

class GameStatus(str, Enum):
    WAITING = "waiting"
    ACTIVE = "active"
    FINISHED = "finished"

class DrawingSubmission(BaseModel):
    game_id: str
    player_id: str
    drawing_data: str  # base64 encoded PNG
    prompt: str
    time_taken: float  # seconds

class AIScoreRequest(BaseModel):
    drawing_data: str  # base64
    prompt: str

class AIScoreResponse(BaseModel):
    confidence: float       # 0.0 - 1.0 how sure AI is
    recognized_as: str      # what AI thinks it is
    bluff_detected: bool    # True if drawing doesn't match prompt
    score: float            # final score 0-100
    breakdown: dict

class GameRoom(BaseModel):
    id: str
    room_code: str
    prompt: str
    status: GameStatus
    player1_id: Optional[str] = None
    player2_id: Optional[str] = None
    player1_score: Optional[float] = None
    player2_score: Optional[float] = None
    winner_id: Optional[str] = None
    created_at: Optional[datetime] = None

class CreateRoomResponse(BaseModel):
    room_code: str
    game_id: str
    prompt: str

class JoinRoomRequest(BaseModel):
    room_code: str
    player_id: str