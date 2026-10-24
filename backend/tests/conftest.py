"""Shared test setup.

The tests never touch your real Supabase project: dummy settings are forced into the
environment before the app is imported, and the database is replaced by FakeSupabase, a small
in-memory stand-in that mirrors the SQL functions from migrations/002 (join_room,
finalize_room, submit_score).
"""
import base64
import io
import os
import uuid
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

import pytest

# supabase-py rejects keys that are not JWT-shaped, so the dummy keys look like JWTs.
os.environ.update(
    {
        "SUPABASE_URL": "https://test-project.supabase.co",
        "SUPABASE_KEY": "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.c2ln",
        "SUPABASE_SERVICE_KEY": "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZSJ9.c2ln",
        "SECRET_KEY": "test-secret",
        "ENVIRONMENT": "development",
        "ALLOWED_ORIGINS": "",
        "MODEL_PATH": "models/__no_such_model__.onnx",  # tests always start on the mock classifier
        "DRAWING_SECONDS": "60",
        "SUBMIT_GRACE_SECONDS": "5",
        "MAX_DRAWING_BYTES": "2000000",
        "RATE_LIMIT_PER_MINUTE": "30",
    }
)

from fastapi.testclient import TestClient  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402
from postgrest.exceptions import APIError  # noqa: E402

import app.core.security as security  # noqa: E402
import app.services.game_service as game_service  # noqa: E402
import app.services.ml_service as ml_service  # noqa: E402
from app.core.rate_limit import RateLimiter  # noqa: E402
from app.main import app  # noqa: E402

_REAL_RATE_CHECK = RateLimiter.check


def _api_error(message: str, code: str = "P0001") -> APIError:
    return APIError({"message": message, "code": code, "hint": None, "details": None})


# =================================================================================================
# In-memory Supabase
# =================================================================================================
class FakeQuery:
    def __init__(self, db: "FakeSupabase", table: str) -> None:
        self.db, self.table = db, table
        self._cols = "*"
        self._filters = []
        self._orders = []
        self._limit = None
        self._insert = None

    def select(self, cols="*"):
        self._cols = cols
        return self

    def insert(self, row):
        self._insert = dict(row)
        return self

    def eq(self, column, value):
        self._filters.append(lambda r: r.get(column) == value)
        return self

    def gt(self, column, value):
        self._filters.append(lambda r: (r.get(column) or 0) > value)
        return self

    def in_(self, column, values):
        values = set(values)
        self._filters.append(lambda r: r.get(column) in values)
        return self

    def or_(self, expression):
        parts = [p.split(".", 2) for p in expression.split(",")]
        self._filters.append(lambda r: any(r.get(c) == v for c, _op, v in parts))
        return self

    def order(self, column, desc=False):
        self._orders.append((column, desc))
        return self

    def limit(self, count):
        self._limit = count
        return self

    def execute(self):
        if self._insert is not None:
            return SimpleNamespace(data=[deepcopy(self.db.insert_row(self.table, self._insert))])

        rows = [r for r in self.db.tables[self.table] if all(f(r) for f in self._filters)]
        for column, desc in reversed(self._orders):
            rows.sort(
                key=lambda r: (r.get(column) is not None, r.get(column) if r.get(column) is not None else 0),
                reverse=desc,
            )
        if self._limit is not None:
            rows = rows[: self._limit]
        rows = deepcopy(rows)
        if self._cols != "*":
            wanted = [c.strip() for c in self._cols.split(",")]
            rows = [{c: r.get(c) for c in wanted} for r in rows]
        return SimpleNamespace(data=rows)


class FakeRPC:
    def __init__(self, db: "FakeSupabase", name: str, params: dict) -> None:
        self.db, self.name, self.params = db, name, params

    def execute(self):
        return SimpleNamespace(data=getattr(self.db, "_rpc_" + self.name)(**self.params))


class FakeSupabase:
    """Stands in for `supabase_admin` (tables, RPCs and auth.get_user)."""

    def __init__(self) -> None:
        self.tables = {"profiles": [], "game_rooms": []}
        self.tokens = {}
        self.now = lambda: datetime.now(timezone.utc)
        self.auth = SimpleNamespace(get_user=self._get_user)

    # ---- helpers for tests ----
    def add_user(self, name: str) -> str:
        user_id = str(uuid.uuid4())
        self.tables["profiles"].append(
            {"id": user_id, "username": name, "email": f"{name}@example.com",
             "total_wins": 0, "total_games": 0, "best_score": 0.0}
        )
        self.tokens[f"token-{name}"] = user_id
        return user_id

    def headers(self, name: str) -> dict:
        return {"Authorization": f"Bearer token-{name}"}

    def profile(self, name: str) -> dict:
        return next(p for p in self.tables["profiles"] if p["username"] == name)

    def room(self, game_id: str) -> dict:
        return next(r for r in self.tables["game_rooms"] if r["id"] == game_id)

    def set_started(self, game_id: str, seconds_ago: float) -> None:
        self.room(game_id)["started_at"] = (self.now() - timedelta(seconds=seconds_ago)).isoformat()

    # ---- supabase-py surface ----
    def table(self, name: str) -> FakeQuery:
        return FakeQuery(self, name)

    def rpc(self, name: str, params: dict) -> FakeRPC:
        return FakeRPC(self, name, params)

    def _get_user(self, token: str):
        if token not in self.tokens:
            raise Exception("invalid token")
        return SimpleNamespace(user=SimpleNamespace(id=self.tokens[token], email="x@example.com"))

    def _profile_exists(self, user_id) -> bool:
        return any(p["id"] == user_id for p in self.tables["profiles"])

    def insert_row(self, table: str, row: dict) -> dict:
        if table != "game_rooms":
            self.tables[table].append(row)
            return row
        if any(r["room_code"] == row["room_code"] for r in self.tables["game_rooms"]):
            raise _api_error("duplicate key value violates unique constraint", "23505")
        if not self._profile_exists(row.get("player1_id")):
            raise _api_error("violates foreign key constraint", "23503")
        full = {
            "id": str(uuid.uuid4()), "status": "waiting", "player2_id": None,
            "player1_score": None, "player2_score": None, "winner_id": None,
            "started_at": None, "finished_at": None, "created_at": self.now().isoformat(),
        }
        full.update(row)
        self.tables["game_rooms"].append(full)
        return full

    # ---- mirrors of the SQL functions ----
    def _rpc_join_room(self, p_room_code, p_player_id):
        for room in self.tables["game_rooms"]:
            if (room["room_code"] == p_room_code.upper() and room["status"] == "waiting"
                    and room["player2_id"] is None and room["player1_id"] != p_player_id):
                if not self._profile_exists(p_player_id):
                    raise _api_error("violates foreign key constraint", "23503")
                room.update(player2_id=p_player_id, status="active", started_at=self.now().isoformat())
                return [deepcopy(room)]
        return []

    def _rpc_finalize_room(self, p_game_id, p_limit_seconds=65):
        room = next((r for r in self.tables["game_rooms"] if r["id"] == p_game_id), None)
        if room is None:
            raise _api_error("room_not_found")
        if room["status"] != "active":
            return deepcopy(room)

        both = room["player1_score"] is not None and room["player2_score"] is not None
        started = datetime.fromisoformat(room["started_at"]) if room["started_at"] else None
        expired = started is not None and self.now() >= started + timedelta(seconds=p_limit_seconds)
        if not (both or expired):
            return deepcopy(room)

        s1, s2 = room["player1_score"] or 0.0, room["player2_score"] or 0.0
        winner = room["player1_id"] if s1 > s2 else room["player2_id"] if s2 > s1 else None
        room.update(player1_score=s1, player2_score=s2, winner_id=winner,
                    status="finished", finished_at=self.now().isoformat())
        for pid, score in ((room["player1_id"], s1), (room["player2_id"], s2)):
            profile = next(p for p in self.tables["profiles"] if p["id"] == pid)
            profile["total_games"] += 1
            profile["total_wins"] += 1 if winner == pid else 0
            profile["best_score"] = max(profile["best_score"], score)
        return deepcopy(room)

    def _rpc_submit_score(self, p_game_id, p_player_id, p_score, p_limit_seconds=65):
        room = next((r for r in self.tables["game_rooms"] if r["id"] == p_game_id), None)
        if room is None:
            raise _api_error("room_not_found")
        if p_player_id not in (room["player1_id"], room["player2_id"]):
            raise _api_error("not_a_player")
        if room["status"] == "waiting":
            raise _api_error("room_not_active")
        if room["status"] == "finished":
            return deepcopy(room)
        key = "player1_score" if room["player1_id"] == p_player_id else "player2_score"
        if room[key] is None:
            room[key] = p_score
        return self._rpc_finalize_room(p_game_id, p_limit_seconds)


# =================================================================================================
# Fixtures
# =================================================================================================
@pytest.fixture(autouse=True)
def _isolate(monkeypatch):
    ml_service.reset_model_cache()
    security.clear_token_cache()
    monkeypatch.setattr(RateLimiter, "check", lambda self, key: 0.0)  # limiter off by default
    yield
    ml_service.reset_model_cache()
    security.clear_token_cache()


@pytest.fixture
def real_rate_limits(monkeypatch):
    """Turn the real rate limiter back on for one test."""
    monkeypatch.setattr(RateLimiter, "check", _REAL_RATE_CHECK)


@pytest.fixture
def db(monkeypatch):
    fake = FakeSupabase()
    monkeypatch.setattr(game_service, "supabase_admin", fake)
    monkeypatch.setattr(security, "supabase_admin", fake)
    return fake


@pytest.fixture
def client(db):
    return TestClient(app, raise_server_exceptions=False)


@pytest.fixture
def players(db):
    """Three registered players: alice, bob, carol -> {name: user_id}."""
    return {name: db.add_user(name) for name in ("alice", "bob", "carol")}


def make_png(kind: str = "circle", size=(600, 420)) -> str:
    """A canvas image like the Flutter app sends: opaque dark background, white strokes."""
    image = Image.new("RGB", size, (26, 26, 46))
    draw = ImageDraw.Draw(image)
    if kind == "circle":
        draw.ellipse((150, 60, 450, 360), outline=(255, 255, 255), width=4)
    elif kind == "tiny":
        draw.ellipse((280, 200, 320, 240), outline=(255, 255, 255), width=4)
    elif kind == "dark_on_light":
        image = Image.new("RGB", size, (255, 255, 255))
        ImageDraw.Draw(image).ellipse((150, 60, 450, 360), outline=(0, 0, 0), width=4)
    elif kind != "blank":
        raise ValueError(kind)
    buffer = io.BytesIO()
    image.save(buffer, "PNG")
    return base64.b64encode(buffer.getvalue()).decode()


@pytest.fixture
def png():
    return make_png