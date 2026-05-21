import random
import string
from typing import Optional
from app.core.supabase import supabase
from app.models.game import GameStatus

PROMPTS = [
    "apple", "bicycle", "bird", "book", "bridge", "butterfly", "cake",
    "car", "cat", "clock", "cloud", "coffee cup", "crown", "dog",
    "dolphin", "elephant", "eye", "fish", "flower", "frog", "guitar",
    "hammer", "hand", "hat", "house", "ice cream", "key", "lamp",
    "lion", "moon", "mountain", "mushroom", "octopus", "pencil",
    "pizza", "rabbit", "shoe", "snake", "star", "sun", "tree",
    "truck", "umbrella", "whale", "zebra"
]

def generate_room_code(length: int = 6) -> str:
    return "".join(random.choices(string.ascii_uppercase + string.digits, k=length))

async def create_game_room(player1_id: str) -> dict:
    room_code = generate_room_code()
    prompt = random.choice(PROMPTS)

    data = {
        "room_code": room_code,
        "prompt": prompt,
        "status": GameStatus.WAITING,
        "player1_id": player1_id,
    }

    result = supabase.table("game_rooms").insert(data).execute()
    room = result.data[0]

    return {
        "room_code": room_code,
        "game_id": room["id"],
        "prompt": prompt
    }

async def join_game_room(room_code: str, player2_id: str) -> Optional[dict]:
    result = supabase.table("game_rooms")\
        .select("*")\
        .eq("room_code", room_code)\
        .eq("status", GameStatus.WAITING)\
        .execute()

    if not result.data:
        return None

    room = result.data[0]

    if room["player1_id"] == player2_id:
        return None  # Can't join your own room

    updated = supabase.table("game_rooms")\
        .update({"player2_id": player2_id, "status": GameStatus.ACTIVE})\
        .eq("id", room["id"])\
        .execute()

    return updated.data[0]

async def submit_score(game_id: str, player_id: str, score: float) -> dict:
    room = supabase.table("game_rooms")\
        .select("*").eq("id", game_id).execute().data[0]

    is_player1 = room["player1_id"] == player_id
    field = "player1_score" if is_player1 else "player2_score"

    supabase.table("game_rooms")\
        .update({field: score})\
        .eq("id", game_id)\
        .execute()

    # Refresh
    room = supabase.table("game_rooms")\
        .select("*").eq("id", game_id).execute().data[0]

    # Both scores submitted → determine winner
    if room["player1_score"] is not None and room["player2_score"] is not None:
        p1 = room["player1_score"]
        p2 = room["player2_score"]
        winner_id = room["player1_id"] if p1 >= p2 else room["player2_id"]

        supabase.table("game_rooms")\
            .update({"status": GameStatus.FINISHED, "winner_id": winner_id})\
            .eq("id", game_id)\
            .execute()

        # Update user stats
        _update_user_stats(room["player1_id"], p1, winner_id)
        _update_user_stats(room["player2_id"], p2, winner_id)

        return {"status": "finished", "winner_id": winner_id}

    return {"status": "waiting_for_opponent"}

def _update_user_stats(user_id: str, score: float, winner_id: str):
    profile = supabase.table("profiles")\
        .select("*").eq("id", user_id).execute().data

    if not profile:
        return

    p = profile[0]
    won = 1 if user_id == winner_id else 0

    supabase.table("profiles").update({
        "total_games": p["total_games"] + 1,
        "total_wins": p["total_wins"] + won,
        "best_score": max(p.get("best_score", 0), score)
    }).eq("id", user_id).execute()