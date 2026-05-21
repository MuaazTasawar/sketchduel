from fastapi import APIRouter
from app.api.routes import auth, game, leaderboard

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(game.router)
api_router.include_router(leaderboard.router)