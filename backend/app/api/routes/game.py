import functools
from typing import List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status

from app.core.rate_limit import limit_by_user
from app.core.security import CurrentUser
from app.models.game import (
    CreateRoomResponse,
    DrawingSubmission,
    GameRoomResponse,
    HistoryItem,
    JoinRoomRequest,
    PredictResponse,
    ScoreResponse,
)
from app.services import game_service
from app.services.game_service import GameServiceError

router = APIRouter(prefix="/game", tags=["game"])

_STATUS_FOR_CODE = {
    game_service.BAD_REQUEST: status.HTTP_400_BAD_REQUEST,
    game_service.NOT_FOUND: status.HTTP_404_NOT_FOUND,
    game_service.FORBIDDEN: status.HTTP_403_FORBIDDEN,
    game_service.CONFLICT: status.HTTP_409_CONFLICT,
    game_service.UNAVAILABLE: status.HTTP_503_SERVICE_UNAVAILABLE,
}


def translate_errors(func):
    """Turn service-layer errors into HTTP errors (services know nothing about HTTP)."""

    @functools.wraps(func)
    def wrapper(*args, **kwargs):
        try:
            return func(*args, **kwargs)
        except GameServiceError as error:
            raise HTTPException(
                _STATUS_FOR_CODE.get(error.code, status.HTTP_500_INTERNAL_SERVER_ERROR),
                error.message,
            )

    return wrapper


@router.post("/room/create", response_model=CreateRoomResponse)
@translate_errors
def create_room(user: CurrentUser = Depends(limit_by_user("create_room", 10))):
    return game_service.create_game_room(user.id)


@router.post("/room/join", response_model=GameRoomResponse)
@translate_errors
def join_room(
    request: JoinRoomRequest, user: CurrentUser = Depends(limit_by_user("join_room", 20))
):
    return game_service.join_game_room(user.id, request.room_code)


@router.get("/room/id/{game_id}", response_model=GameRoomResponse)
@translate_errors
def get_room(game_id: UUID, user: CurrentUser = Depends(limit_by_user("get_room", 90))):
    return game_service.get_game_room(user.id, str(game_id))


@router.post("/score", response_model=ScoreResponse)
@translate_errors
def submit_score(
    submission: DrawingSubmission, user: CurrentUser = Depends(limit_by_user("score", 10))
):
    return game_service.submit_drawing(user.id, str(submission.game_id), submission.drawing_data)


@router.post("/predict", response_model=PredictResponse)
@translate_errors
def predict(
    submission: DrawingSubmission, user: CurrentUser = Depends(limit_by_user("predict", 30))
):
    return game_service.predict_for_game(user.id, str(submission.game_id), submission.drawing_data)


@router.get("/history", response_model=List[HistoryItem])
@translate_errors
def history(
    limit: int = Query(20, ge=1, le=100),
    user: CurrentUser = Depends(limit_by_user("history", 30)),
):
    return game_service.get_history(user.id, limit)