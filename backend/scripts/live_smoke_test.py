"""Play one full match against your REAL Supabase project using two temporary players.

    cd backend
    python scripts/live_smoke_test.py --check-settings     # only reads the auth settings
    python scripts/live_smoke_test.py                       # full match; cleans up after itself

Requires backend/.env and 'Confirm email' switched OFF in the Supabase dashboard.
"""
import base64
import io
import logging
import secrets
import sys
from pathlib import Path

import httpx

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fastapi.testclient import TestClient  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

from app.core.config import settings  # noqa: E402

for noisy in ("httpx", "httpcore", "hpack"):
    logging.getLogger(noisy).setLevel(logging.WARNING)


def step(label, ok, detail=""):
    print(("OK    " if ok else "FAIL  ") + label)
    if not ok:
        print("      " + str(detail)[:400])
        raise SystemExit(1)


def check_settings():
    cfg = httpx.get(
        f"{settings.SUPABASE_URL}/auth/v1/settings",
        headers={"apikey": settings.SUPABASE_KEY},
        timeout=30,
    ).json()
    step(
        "e-mail sign-up is enabled",
        cfg.get("external", {}).get("email") is True and not cfg.get("disable_signup"),
        "Authentication -> Sign In / Providers -> Email: turn 'Enable email provider' ON and save",
    )
    step(
        "'Confirm email' is OFF (no mail will be sent)",
        cfg.get("mailer_autoconfirm") is True,
        "Scroll down inside the Email panel, turn 'Confirm email' OFF, click Save, then rerun",
    )


def drawing():
    img = Image.new("RGB", (600, 420), (26, 26, 46))
    ImageDraw.Draw(img).ellipse((150, 60, 450, 360), outline=(255, 255, 255), width=4)
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return base64.b64encode(buf.getvalue()).decode()


def full_match():
    from app.core.supabase import supabase_admin
    from app.main import app

    client = TestClient(app)
    tag = secrets.token_hex(3)
    user_ids, game_ids = [], []
    try:
        tokens = {}
        for who in ("a", "b"):
            email, name = f"sketchduel.test.{tag}.{who}@gmail.com", f"sd_{tag}_{who}"
            r = client.post("/api/v1/auth/register", json={"email": email, "password": "Test1234!", "username": name})
            step(f"register player {who.upper()}", r.status_code == 200, r.text)
            user_ids.append(r.json()["user_id"])
            r = client.post("/api/v1/auth/login", json={"email": email, "password": "Test1234!"})
            step(f"login player {who.upper()}", r.status_code == 200, r.text)
            tokens[who] = {"Authorization": "Bearer " + r.json()["access_token"]}

        r = client.post("/api/v1/game/room/create", headers=tokens["a"])
        step("A creates a room", r.status_code == 200, r.text)
        room = r.json()
        game_ids.append(room["game_id"])
        print(f"      code {room['room_code']}, prompt '{room['prompt']}'")

        r = client.post("/api/v1/game/room/join", json={"room_code": room["room_code"]}, headers=tokens["b"])
        step("B joins -> game is active", r.status_code == 200 and r.json()["status"] == "active", r.text)

        r = client.post("/api/v1/game/predict", json={"game_id": room["game_id"], "drawing_data": drawing()}, headers=tokens["a"])
        step("live AI preview works", r.status_code == 200, r.text)
        p = r.json()
        print(f"      AI model in use: {p['model']}   (sees '{p['recognized_as']}' at {p['confidence']:.0%})")

        r = client.post("/api/v1/game/score", json={"game_id": room["game_id"], "drawing_data": drawing()}, headers=tokens["a"])
        step("A submits -> waiting for B", r.status_code == 200 and r.json()["status"] == "active", r.text)
        r = client.post("/api/v1/game/score", json={"game_id": room["game_id"], "drawing_data": drawing()}, headers=tokens["b"])
        step("B submits -> match finished", r.status_code == 200 and r.json()["status"] == "finished", r.text)
        done = r.json()["room"]
        print(f"      scores: A={done['player1_score']}  B={done['player2_score']}  draw={done['is_draw']}")

        r = client.get("/api/v1/leaderboard/top", headers=tokens["a"])
        names = [e["username"] for e in r.json()]
        step("both players on the leaderboard", r.status_code == 200 and f"sd_{tag}_a" in names and f"sd_{tag}_b" in names, r.text)
        r = client.get("/api/v1/game/history", headers=tokens["a"])
        step("match shows in A's history", r.status_code == 200 and len(r.json()) == 1, r.text)

        print("\nALL LIVE CHECKS PASSED")
    finally:
        for gid in game_ids:
            supabase_admin.table("game_rooms").delete().eq("id", gid).execute()
        for uid in user_ids:
            try:
                supabase_admin.auth.admin.delete_user(uid)
            except Exception as error:
                print("cleanup warning:", error)
        print("(test players and game deleted)")


if __name__ == "__main__":
    check_settings()
    if "--check-settings" not in sys.argv:
        full_match()