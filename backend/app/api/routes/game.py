from fastapi import APIRouter, HTTPException
from app.models.game import (
    AIScoreRequest, AIScoreResponse,
    CreateRoomResponse, JoinRoomRequest,
    DrawingSubmission
)
from app.services.ml_service import score_drawing
from app.services.game_service import (
    create_game_room, join_game_room, submit_score
)

router = APIRouter(prefix="/game", tags=["game"])

@router.post("/room/create")
async def create_room(player_id: str):
    try:
        room = await create_game_room(player_id)
        return room
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/room/join")
async def join_room(req: JoinRoomRequest):
    room = await join_game_room(req.room_code, req.player_id)
    if not room:
        raise HTTPException(status_code=404, detail="Room not found or already full")
    return room

@router.get("/room/{room_code}")
async def get_room(room_code: str):
    from app.core.supabase import supabase
    result = supabase.table("game_rooms")\
        .select("*").eq("room_code", room_code).execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Room not found")
    return result.data[0]

@router.post("/score")
async def score_submission(submission: DrawingSubmission):
    try:
        result = await score_drawing(
            submission.drawing_data,
            submission.prompt,
            submission.time_taken
        )

        # Save score and check if game is finished
        game_status = await submit_score(
            submission.game_id,
            submission.player_id,
            result["score"]
        )

        return {**result, **game_status}

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/history/{user_id}")
async def game_history(user_id: str):
    from app.core.supabase import supabase
    result = supabase.table("game_rooms")\
        .select("*")\
        .or_(f"player1_id.eq.{user_id},player2_id.eq.{user_id}")\
        .eq("status", "finished")\
        .order("created_at", desc=True)\
        .limit(20)\
        .execute()
    return result.data