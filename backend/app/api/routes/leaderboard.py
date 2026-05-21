from fastapi import APIRouter
from app.core.supabase import supabase

router = APIRouter(prefix="/leaderboard", tags=["leaderboard"])

@router.get("/top")
async def get_leaderboard(limit: int = 20):
    result = supabase.table("profiles")\
        .select("username,total_wins,total_games,best_score")\
        .order("total_wins", desc=True)\
        .limit(limit)\
        .execute()

    leaderboard = []
    for i, player in enumerate(result.data):
        games = player["total_games"]
        wins = player["total_wins"]
        win_rate = round((wins / games * 100), 1) if games > 0 else 0.0
        leaderboard.append({
            "rank": i + 1,
            "username": player["username"],
            "total_wins": wins,
            "total_games": games,
            "win_rate": win_rate,
            "best_score": player["best_score"]
        })

    return leaderboard