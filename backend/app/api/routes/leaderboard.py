from typing import List

from fastapi import APIRouter, Depends, Query

from app.core.rate_limit import limit_by_user
from app.core.security import CurrentUser
from app.models.game import LeaderboardEntry
from app.services import game_service

router = APIRouter(prefix="/leaderboard", tags=["leaderboard"])


@router.get("/top", response_model=List[LeaderboardEntry])
def get_leaderboard(
    limit: int = Query(20, ge=1, le=100),
    _: CurrentUser = Depends(limit_by_user("leaderboard", 30)),
):
    return game_service.get_leaderboard(limit)