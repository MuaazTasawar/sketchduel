import logging
import re
import secrets
import string
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from postgrest.exceptions import APIError

from app.core.config import settings
from app.core.supabase import supabase_admin
from app.services import ml_service
from app.services.ml_service import QUICKDRAW_CLASSES, InvalidDrawingError

logger = logging.getLogger(__name__)

# Every prompt MUST be a category the model knows (and that exists in the QuickDraw dataset).
PROMPTS: List[str] = [
    "apple", "bicycle", "bird", "book", "bridge", "butterfly", "cake", "car", "cat",
    "clock", "cloud", "coffee cup", "crown", "dog", "dolphin", "elephant", "eye", "fish",
    "flower", "frog", "guitar", "hammer", "hand", "hat", "house", "ice cream", "key",
    "light bulb", "lion", "moon", "mountain", "mushroom", "octopus", "pencil", "pizza",
    "rabbit", "shoe", "snake", "star", "sun", "tree", "truck", "umbrella", "whale", "zebra",
]

_unknown_prompts = [p for p in PROMPTS if p not in QUICKDRAW_CLASSES]
if _unknown_prompts:
    raise RuntimeError(f"Prompts that are not model classes: {_unknown_prompts}")

ROOM_CODE_LENGTH = 6
ROOM_CODE_ALPHABET = string.ascii_uppercase + string.digits

# Error codes (translated into HTTP statuses by the routes)
BAD_REQUEST = "bad_request"
NOT_FOUND = "not_found"
FORBIDDEN = "forbidden"
CONFLICT = "conflict"
UNAVAILABLE = "unavailable"


class GameServiceError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.message = message


# =================================================================================================
# Small pure helpers (unit-tested without a database)
# =================================================================================================
def generate_room_code(length: int = ROOM_CODE_LENGTH) -> str:
    return "".join(secrets.choice(ROOM_CODE_ALPHABET) for _ in range(length))


def pick_prompt() -> str:
    return secrets.choice(PROMPTS)


def hard_limit_seconds() -> int:
    """Drawing time plus the network grace period. Matches the limit passed to the SQL functions."""
    return settings.DRAWING_SECONDS + settings.SUBMIT_GRACE_SECONDS


def parse_timestamp(value: Any) -> Optional[datetime]:
    """Parse the timestamptz strings PostgREST returns (any number of fractional digits)."""
    if not value:
        return None
    text = str(value).strip().replace("Z", "+00:00")
    text = re.sub(r"\.(\d+)", lambda m: "." + (m.group(1) + "000000")[:6], text, count=1)
    parsed = datetime.fromisoformat(text)
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def elapsed_seconds(room: Dict[str, Any], now: datetime) -> Optional[float]:
    started = parse_timestamp(room.get("started_at"))
    if started is None:
        return None
    return max((now - started).total_seconds(), 0.0)


def seconds_remaining(room: Dict[str, Any], now: datetime) -> Optional[float]:
    if room.get("status") != "active":
        return None
    elapsed = elapsed_seconds(room, now)
    if elapsed is None:
        return None
    return round(max(settings.DRAWING_SECONDS - elapsed, 0.0), 1)


def decide_winner(
    player1_id: Optional[str], player2_id: Optional[str], score1: float, score2: float
) -> Optional[str]:
    """Higher score wins; equal scores are a draw (None). Mirrors finalize_room() in SQL."""
    if score1 > score2:
        return player1_id
    if score2 > score1:
        return player2_id
    return None


def is_participant(room: Dict[str, Any], user_id: str) -> bool:
    return user_id in (room.get("player1_id"), room.get("player2_id"))


def room_view(room: Dict[str, Any], user_id: str, now: Optional[datetime] = None) -> Dict[str, Any]:
    """The room as one of its players may see it (opponent's score hidden until the end)."""
    now = now or utcnow()
    finished = room.get("status") == "finished"
    is_player1 = room.get("player1_id") == user_id

    score1, score2 = room.get("player1_score"), room.get("player2_score")
    if not finished:
        if is_player1:
            score2 = None
        else:
            score1 = None

    return {
        "id": room["id"],
        "room_code": room["room_code"],
        "prompt": room["prompt"],
        "status": room["status"],
        "player1_id": room.get("player1_id"),
        "player2_id": room.get("player2_id"),
        "player1_score": score1,
        "player2_score": score2,
        "winner_id": room.get("winner_id"),
        "is_draw": finished and room.get("winner_id") is None,
        "is_player1": is_player1,
        "seconds_remaining": seconds_remaining(room, now),
        "time_limit_seconds": settings.DRAWING_SECONDS,
        "started_at": room.get("started_at"),
        "finished_at": room.get("finished_at"),
        "created_at": room.get("created_at"),
    }


# =================================================================================================
# Database access
# =================================================================================================
def _error_message(error: Exception) -> str:
    return str(getattr(error, "message", None) or error)


def _error_code(error: Exception) -> Optional[str]:
    return getattr(error, "code", None)


def _translate_rpc_error(error: Exception) -> GameServiceError:
    message = _error_message(error)
    if "room_not_found" in message:
        return GameServiceError(NOT_FOUND, "Game not found")
    if "not_a_player" in message:
        return GameServiceError(NOT_FOUND, "Game not found")
    if "room_not_active" in message:
        return GameServiceError(CONFLICT, "The game has not started yet")
    logger.error("Unexpected database error: %s", message)
    return GameServiceError(UNAVAILABLE, "Database error, please try again")


def _fetch_room(game_id: str) -> Optional[Dict[str, Any]]:
    result = supabase_admin.table("game_rooms").select("*").eq("id", game_id).limit(1).execute()
    return result.data[0] if result.data else None


def _finalize(game_id: str) -> Dict[str, Any]:
    """Finish the room if both scores are in or the deadline passed; otherwise a no-op."""
    try:
        result = supabase_admin.rpc(
            "finalize_room", {"p_game_id": game_id, "p_limit_seconds": hard_limit_seconds()}
        ).execute()
    except APIError as error:
        raise _translate_rpc_error(error)
    data = result.data
    if isinstance(data, list):
        data = data[0] if data else None
    if not data:
        raise GameServiceError(NOT_FOUND, "Game not found")
    return data


def _load_player_room(user_id: str, game_id: str) -> Dict[str, Any]:
    """Room row (finalised if due). Non-players get 'not found' so ids can't be probed."""
    room = _finalize(game_id)
    if not is_participant(room, user_id):
        raise GameServiceError(NOT_FOUND, "Game not found")
    return room


# =================================================================================================
# Use cases
# =================================================================================================
def create_game_room(user_id: str) -> Dict[str, str]:
    prompt = pick_prompt()
    for _ in range(8):
        code = generate_room_code()
        try:
            result = (
                supabase_admin.table("game_rooms")
                .insert(
                    {"room_code": code, "prompt": prompt, "status": "waiting", "player1_id": user_id}
                )
                .execute()
            )
        except APIError as error:
            db_code = _error_code(error)
            if db_code == "23505":  # room code collision: try another code
                continue
            if db_code == "23503":
                raise GameServiceError(CONFLICT, "Your profile is missing. Please register again.")
            logger.error("create_game_room failed: %s", _error_message(error))
            raise GameServiceError(UNAVAILABLE, "Could not create the room")
        row = result.data[0]
        return {"room_code": row["room_code"], "game_id": row["id"], "prompt": row["prompt"]}

    raise GameServiceError(UNAVAILABLE, "Could not allocate a room code, please retry")


def join_game_room(user_id: str, room_code: str, now: Optional[datetime] = None) -> Dict[str, Any]:
    code = room_code.strip().upper()
    try:
        result = supabase_admin.rpc(
            "join_room", {"p_room_code": code, "p_player_id": user_id}
        ).execute()
    except APIError as error:
        if _error_code(error) == "23503":
            raise GameServiceError(CONFLICT, "Your profile is missing. Please register again.")
        raise _translate_rpc_error(error)

    rows = result.data or []
    if isinstance(rows, dict):
        rows = [rows]
    if rows:
        return room_view(rows[0], user_id, now)

    # Nothing was updated: explain why.
    lookup = supabase_admin.table("game_rooms").select("*").eq("room_code", code).limit(1).execute()
    if not lookup.data:
        raise GameServiceError(NOT_FOUND, "Room not found")
    if lookup.data[0].get("player1_id") == user_id:
        raise GameServiceError(CONFLICT, "You cannot join your own room")
    raise GameServiceError(CONFLICT, "This room is full or the game already started")


def get_game_room(user_id: str, game_id: str, now: Optional[datetime] = None) -> Dict[str, Any]:
    return room_view(_load_player_room(user_id, game_id), user_id, now)


def _my_score(room: Dict[str, Any], user_id: str) -> Optional[float]:
    return room.get("player1_score") if room.get("player1_id") == user_id else room.get("player2_score")


def submit_drawing(
    user_id: str, game_id: str, drawing_data: str, now: Optional[datetime] = None
) -> Dict[str, Any]:
    now = now or utcnow()
    room = _load_player_room(user_id, game_id)

    if room["status"] == "waiting":
        raise GameServiceError(CONFLICT, "The game has not started yet")

    def state(breakdown: Optional[Dict[str, Any]], submitted: bool, current: Dict[str, Any]) -> Dict[str, Any]:
        view = room_view(current, user_id, now)
        response: Dict[str, Any] = dict(breakdown or {})
        response.update(
            submitted=submitted,
            status=view["status"],
            winner_id=view["winner_id"],
            is_draw=view["is_draw"],
            room=view,
        )
        return response

    # Already finished, or this player already handed in a drawing: never score twice.
    if room["status"] == "finished" or _my_score(room, user_id) is not None:
        return state(None, False, room)

    elapsed = elapsed_seconds(room, now) or 0.0
    late = elapsed > hard_limit_seconds()

    try:
        if late:
            # Handed in after the deadline: counts as a forfeit (score 0).
            breakdown = ml_service.calculate_score(
                "", 0.0, room["prompt"], settings.DRAWING_SECONDS, settings.DRAWING_SECONDS, blank=True
            )
            breakdown.update(prompt_confidence=0.0, blank=True, model=ml_service.model_info()["backend"])
        else:
            breakdown = ml_service.score_drawing_sync(
                drawing_data, room["prompt"], elapsed, max_time=float(settings.DRAWING_SECONDS)
            )
    except InvalidDrawingError as error:
        raise GameServiceError(BAD_REQUEST, str(error))

    breakdown["late"] = late
    breakdown["time_taken"] = round(min(elapsed, float(settings.DRAWING_SECONDS)), 2)

    try:
        result = supabase_admin.rpc(
            "submit_score",
            {
                "p_game_id": game_id,
                "p_player_id": user_id,
                "p_score": breakdown["score"],
                "p_limit_seconds": hard_limit_seconds(),
            },
        ).execute()
    except APIError as error:
        raise _translate_rpc_error(error)

    updated = result.data[0] if isinstance(result.data, list) else result.data
    return state(breakdown, True, updated)


def predict_for_game(
    user_id: str, game_id: str, drawing_data: str, now: Optional[datetime] = None
) -> Dict[str, Any]:
    """Live 'what does the AI see?' preview. Nothing is stored or scored."""
    now = now or utcnow()
    room = _load_player_room(user_id, game_id)

    if room["status"] != "active":
        raise GameServiceError(CONFLICT, "The game is not active")
    remaining = seconds_remaining(room, now)
    if remaining is not None and remaining <= 0:
        raise GameServiceError(CONFLICT, "Time is up")

    try:
        result = ml_service.predict_drawing(drawing_data, room["prompt"])
    except InvalidDrawingError as error:
        raise GameServiceError(BAD_REQUEST, str(error))

    result["seconds_remaining"] = remaining
    return result


def get_history(user_id: str, limit: int = 20) -> List[Dict[str, Any]]:
    rows = (
        supabase_admin.table("game_rooms")
        .select("*")
        .eq("status", "finished")
        .or_(f"player1_id.eq.{user_id},player2_id.eq.{user_id}")
        .order("finished_at", desc=True)
        .limit(limit)
        .execute()
        .data
        or []
    )

    opponent_ids = list(
        {
            (row["player2_id"] if row["player1_id"] == user_id else row["player1_id"])
            for row in rows
            if row.get("player1_id") and row.get("player2_id")
        }
    )
    names: Dict[str, str] = {}
    if opponent_ids:
        profiles = supabase_admin.table("profiles").select("id,username").in_("id", opponent_ids).execute()
        names = {p["id"]: p["username"] for p in (profiles.data or [])}

    history = []
    for row in rows:
        mine_is_p1 = row["player1_id"] == user_id
        opponent_id = row["player2_id"] if mine_is_p1 else row["player1_id"]
        if row.get("winner_id") is None:
            result = "draw"
        else:
            result = "win" if row["winner_id"] == user_id else "loss"
        history.append(
            {
                "game_id": row["id"],
                "room_code": row["room_code"],
                "prompt": row["prompt"],
                "result": result,
                "your_score": row["player1_score"] if mine_is_p1 else row["player2_score"],
                "opponent_score": row["player2_score"] if mine_is_p1 else row["player1_score"],
                "opponent_username": names.get(opponent_id),
                "finished_at": row.get("finished_at"),
            }
        )
    return history


def get_leaderboard(limit: int = 20) -> List[Dict[str, Any]]:
    rows = (
        supabase_admin.table("profiles")
        .select("username,total_wins,total_games,best_score")
        .gt("total_games", 0)
        .order("total_wins", desc=True)
        .order("best_score", desc=True)
        .limit(limit)
        .execute()
        .data
        or []
    )
    board = []
    for index, player in enumerate(rows):
        games = player.get("total_games") or 0
        wins = player.get("total_wins") or 0
        board.append(
            {
                "rank": index + 1,
                "username": player["username"],
                "total_wins": wins,
                "total_games": games,
                "win_rate": round(wins / games * 100, 1) if games else 0.0,
                "best_score": player.get("best_score") or 0.0,
            }
        )
    return board