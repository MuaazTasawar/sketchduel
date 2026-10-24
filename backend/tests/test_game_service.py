import re
from datetime import datetime, timedelta, timezone

import pytest

from app.services import game_service as gs
from app.services import ml_service as ml

U = "/api/v1/game"


# =================================================================================================
# Pure helpers
# =================================================================================================
class TestPrompts:
    def test_every_prompt_is_a_model_class(self):
        assert [p for p in gs.PROMPTS if p not in ml.QUICKDRAW_CLASSES] == []

    def test_prompts_are_unique(self):
        assert len(gs.PROMPTS) == len(set(gs.PROMPTS))

    def test_the_old_lamp_prompt_is_gone(self):
        assert "lamp" not in gs.PROMPTS and "lamp" not in ml.QUICKDRAW_CLASSES

    def test_pick_prompt_comes_from_the_pool(self):
        assert all(gs.pick_prompt() in gs.PROMPTS for _ in range(50))


class TestRoomCodes:
    def test_format(self):
        assert all(re.fullmatch(r"[A-Z0-9]{6}", gs.generate_room_code()) for _ in range(200))

    def test_codes_vary(self):
        assert len({gs.generate_room_code() for _ in range(200)}) > 190


class TestParseTimestamp:
    def test_short_fraction(self):
        assert gs.parse_timestamp("2026-10-23T06:15:18.54+00:00").microsecond == 540000

    def test_long_fraction_is_truncated(self):
        assert gs.parse_timestamp("2026-10-23T06:15:18.123456789+00:00").microsecond == 123456

    def test_z_suffix_and_naive_values_are_utc(self):
        assert gs.parse_timestamp("2026-10-23T06:15:18Z").utcoffset() == timedelta(0)
        assert gs.parse_timestamp("2026-10-23T06:15:18").utcoffset() == timedelta(0)

    def test_empty_values(self):
        assert gs.parse_timestamp(None) is None and gs.parse_timestamp("") is None


class TestDecideWinner:
    def test_higher_score_wins(self):
        assert gs.decide_winner("p1", "p2", 80, 60) == "p1"
        assert gs.decide_winner("p1", "p2", 60, 80) == "p2"

    def test_equal_scores_are_a_draw(self):
        assert gs.decide_winner("p1", "p2", 70, 70) is None
        assert gs.decide_winner("p1", "p2", 0, 0) is None


class TestRoomView:
    ROOM = {
        "id": "g", "room_code": "ABC123", "prompt": "cat", "status": "active",
        "player1_id": "p1", "player2_id": "p2", "player1_score": 50.0, "player2_score": 70.0,
        "winner_id": None, "started_at": "2026-10-23T06:00:00+00:00", "finished_at": None,
        "created_at": "2026-10-23T05:59:00+00:00",
    }
    NOW = datetime(2026, 10, 23, 6, 0, 20, tzinfo=timezone.utc)

    def test_opponent_score_is_hidden_while_active(self):
        mine = gs.room_view(self.ROOM, "p1", self.NOW)
        assert mine["player1_score"] == 50.0 and mine["player2_score"] is None
        theirs = gs.room_view(self.ROOM, "p2", self.NOW)
        assert theirs["player2_score"] == 70.0 and theirs["player1_score"] is None

    def test_both_scores_visible_when_finished(self):
        finished = {**self.ROOM, "status": "finished", "winner_id": "p2"}
        view = gs.room_view(finished, "p1", self.NOW)
        assert view["player1_score"] == 50.0 and view["player2_score"] == 70.0
        assert view["is_draw"] is False and view["seconds_remaining"] is None

    def test_draw_flag(self):
        assert gs.room_view({**self.ROOM, "status": "finished"}, "p1", self.NOW)["is_draw"] is True

    def test_seconds_remaining_counts_down(self):
        assert gs.room_view(self.ROOM, "p1", self.NOW)["seconds_remaining"] == 40.0
        late = self.NOW + timedelta(seconds=100)
        assert gs.room_view(self.ROOM, "p1", late)["seconds_remaining"] == 0.0

    def test_is_player1_flag(self):
        assert gs.room_view(self.ROOM, "p1", self.NOW)["is_player1"] is True
        assert gs.room_view(self.ROOM, "p2", self.NOW)["is_player1"] is False


# =================================================================================================
# Service behaviour on the in-memory database
# =================================================================================================
def start_game(players):
    """alice creates, bob joins -> an active game. Returns the game id."""
    created = gs.create_game_room(players["alice"])
    gs.join_game_room(players["bob"], created["room_code"])
    return created["game_id"]


class TestCreateAndJoin:
    def test_create_room(self, db, players):
        result = gs.create_game_room(players["alice"])
        assert re.fullmatch(r"[A-Z0-9]{6}", result["room_code"]) and result["prompt"] in gs.PROMPTS
        assert db.room(result["game_id"])["status"] == "waiting"

    def test_room_code_collision_is_retried(self, db, players, monkeypatch):
        first = gs.create_game_room(players["alice"])
        codes = iter([first["room_code"], first["room_code"], "FRESH1"])
        monkeypatch.setattr(gs, "generate_room_code", lambda: next(codes))
        assert gs.create_game_room(players["bob"])["room_code"] == "FRESH1"

    def test_create_without_a_profile_is_a_conflict(self, db):
        with pytest.raises(gs.GameServiceError) as error:
            gs.create_game_room("00000000-0000-0000-0000-000000000000")
        assert error.value.code == gs.CONFLICT

    def test_join_starts_the_game_and_the_clock(self, db, players):
        created = gs.create_game_room(players["alice"])
        view = gs.join_game_room(players["bob"], created["room_code"].lower())
        assert view["status"] == "active" and view["is_player1"] is False
        assert 58 <= view["seconds_remaining"] <= 60
        assert db.room(created["game_id"])["player2_id"] == players["bob"]

    def test_cannot_join_your_own_room(self, db, players):
        created = gs.create_game_room(players["alice"])
        with pytest.raises(gs.GameServiceError) as error:
            gs.join_game_room(players["alice"], created["room_code"])
        assert error.value.code == gs.CONFLICT and "own room" in error.value.message

    def test_unknown_code(self, db, players):
        with pytest.raises(gs.GameServiceError) as error:
            gs.join_game_room(players["bob"], "NOPE99")
        assert error.value.code == gs.NOT_FOUND

    def test_full_room(self, db, players):
        created = gs.create_game_room(players["alice"])
        gs.join_game_room(players["bob"], created["room_code"])
        with pytest.raises(gs.GameServiceError) as error:
            gs.join_game_room(players["carol"], created["room_code"])
        assert error.value.code == gs.CONFLICT


class TestGetRoom:
    def test_players_can_read_and_outsiders_cannot(self, db, players):
        game_id = start_game(players)
        assert gs.get_game_room(players["alice"], game_id)["id"] == game_id
        assert gs.get_game_room(players["bob"], game_id)["id"] == game_id
        with pytest.raises(gs.GameServiceError) as error:
            gs.get_game_room(players["carol"], game_id)
        assert error.value.code == gs.NOT_FOUND

    def test_unknown_game(self, db, players):
        with pytest.raises(gs.GameServiceError) as error:
            gs.get_game_room(players["alice"], "00000000-0000-0000-0000-000000000000")
        assert error.value.code == gs.NOT_FOUND

    def test_reading_an_expired_game_finishes_it(self, db, players):
        game_id = start_game(players)
        db.set_started(game_id, seconds_ago=120)
        view = gs.get_game_room(players["alice"], game_id)
        assert view["status"] == "finished" and view["is_draw"] is True
        assert view["player1_score"] == 0 and view["player2_score"] == 0


class TestSubmitDrawing:
    def test_first_submission_waits_for_the_opponent(self, db, players, png):
        game_id = start_game(players)
        result = gs.submit_drawing(players["alice"], game_id, png())
        assert result["submitted"] is True and result["status"] == "active"
        assert result["score"] is not None and result["room"]["player2_score"] is None
        assert db.room(game_id)["player1_score"] == result["score"]

    def test_second_submission_finishes_the_match(self, db, players, png, monkeypatch):
        scores = iter([("cat", 0.9, 0.9), ("cat", 0.5, 0.5)])
        monkeypatch.setattr(ml, "classify", lambda processed, prompt: next(scores))
        game_id = start_game(players)
        gs.submit_drawing(players["alice"], game_id, png())
        result = gs.submit_drawing(players["bob"], game_id, png())
        assert result["status"] == "finished" and result["winner_id"] == players["alice"]
        assert result["is_draw"] is False
        assert db.profile("alice")["total_wins"] == 1 and db.profile("bob")["total_wins"] == 0
        assert db.profile("alice")["total_games"] == 1 and db.profile("bob")["total_games"] == 1

    def test_equal_scores_are_a_draw(self, db, players, png, monkeypatch):
        monkeypatch.setattr(ml, "classify", lambda processed, prompt: ("cat", 0.5, 0.5))
        monkeypatch.setattr(gs, "elapsed_seconds", lambda room, now: 10.0)
        game_id = start_game(players)
        gs.submit_drawing(players["alice"], game_id, png())
        result = gs.submit_drawing(players["bob"], game_id, png())
        assert result["status"] == "finished" and result["is_draw"] is True and result["winner_id"] is None
        assert db.profile("alice")["total_wins"] == 0 and db.profile("bob")["total_wins"] == 0
        assert db.profile("alice")["total_games"] == 1

    def test_resubmitting_is_ignored(self, db, players, png):
        game_id = start_game(players)
        first = gs.submit_drawing(players["alice"], game_id, png())
        again = gs.submit_drawing(players["alice"], game_id, png())
        assert again["submitted"] is False and again.get("score") is None
        assert db.room(game_id)["player1_score"] == first["score"]

    def test_submitting_after_the_match_is_over_changes_nothing(self, db, players, png):
        game_id = start_game(players)
        gs.submit_drawing(players["alice"], game_id, png())
        gs.submit_drawing(players["bob"], game_id, png())
        again = gs.submit_drawing(players["alice"], game_id, png())
        assert again["submitted"] is False and db.profile("alice")["total_games"] == 1

    def test_invalid_drawing_is_rejected_and_not_recorded(self, db, players):
        game_id = start_game(players)
        with pytest.raises(gs.GameServiceError) as error:
            gs.submit_drawing(players["alice"], game_id, "not an image")
        assert error.value.code == gs.BAD_REQUEST
        assert db.room(game_id)["player1_score"] is None

    def test_blank_canvas_scores_zero(self, db, players, png):
        game_id = start_game(players)
        result = gs.submit_drawing(players["alice"], game_id, png("blank"))
        assert result["score"] == 0.0 and result["blank"] is True

    def test_outsiders_cannot_submit(self, db, players, png):
        game_id = start_game(players)
        with pytest.raises(gs.GameServiceError) as error:
            gs.submit_drawing(players["carol"], game_id, png())
        assert error.value.code == gs.NOT_FOUND

    def test_cannot_submit_before_the_game_starts(self, db, players, png):
        created = gs.create_game_room(players["alice"])
        with pytest.raises(gs.GameServiceError) as error:
            gs.submit_drawing(players["alice"], created["game_id"], png())
        assert error.value.code == gs.CONFLICT

    def test_the_prompt_comes_from_the_room_not_the_client(self, db, players, png, monkeypatch):
        seen = []
        monkeypatch.setattr(ml, "classify", lambda processed, prompt: seen.append(prompt) or ("cat", 0.5, 0.5))
        game_id = start_game(players)
        gs.submit_drawing(players["alice"], game_id, png())
        assert seen == [db.room(game_id)["prompt"]]

    def test_elapsed_time_comes_from_the_server_clock(self, db, players, png, monkeypatch):
        monkeypatch.setattr(ml, "classify", lambda processed, prompt: ("cat", 0.5, 0.5))
        game_id = start_game(players)
        db.set_started(game_id, seconds_ago=30)
        result = gs.submit_drawing(players["alice"], game_id, png())
        assert 29 <= result["time_taken"] <= 31
        assert 11.5 <= result["speed_bonus"] <= 13.5  # about half the time left -> about 12.5

    def test_submission_after_the_deadline_is_a_forfeit(self, db, players, png):
        game_id = start_game(players)
        later = datetime.now(timezone.utc) + timedelta(seconds=70)  # app clock ahead of the db clock
        result = gs.submit_drawing(players["alice"], game_id, png(), now=later)
        assert result["late"] is True and result["score"] == 0.0


class TestForfeit:
    def test_player_who_never_submits_loses(self, db, players, png):
        game_id = start_game(players)
        gs.submit_drawing(players["alice"], game_id, png())
        db.set_started(game_id, seconds_ago=120)
        view = gs.get_game_room(players["alice"], game_id)
        assert view["status"] == "finished" and view["winner_id"] == players["alice"]
        assert view["player2_score"] == 0
        assert db.profile("bob")["total_games"] == 1 and db.profile("bob")["total_wins"] == 0


class TestPredict:
    def test_live_preview(self, db, players, png):
        game_id = start_game(players)
        result = gs.predict_for_game(players["alice"], game_id, png())
        assert result["blank"] is False and 0 <= result["confidence"] <= 1
        assert 0 < result["seconds_remaining"] <= 60
        assert db.room(game_id)["player1_score"] is None  # nothing stored

    def test_preview_of_a_blank_canvas(self, db, players, png):
        game_id = start_game(players)
        assert gs.predict_for_game(players["alice"], game_id, png("blank"))["blank"] is True

    def test_not_available_before_the_game_starts(self, db, players, png):
        created = gs.create_game_room(players["alice"])
        with pytest.raises(gs.GameServiceError) as error:
            gs.predict_for_game(players["alice"], created["game_id"], png())
        assert error.value.code == gs.CONFLICT

    def test_not_available_after_the_time_is_up(self, db, players, png):
        game_id = start_game(players)
        later = datetime.now(timezone.utc) + timedelta(seconds=61)
        with pytest.raises(gs.GameServiceError) as error:
            gs.predict_for_game(players["alice"], game_id, png(), now=later)
        assert error.value.code == gs.CONFLICT

    def test_outsiders_and_bad_images(self, db, players, png):
        game_id = start_game(players)
        with pytest.raises(gs.GameServiceError) as error:
            gs.predict_for_game(players["carol"], game_id, png())
        assert error.value.code == gs.NOT_FOUND
        with pytest.raises(gs.GameServiceError) as error:
            gs.predict_for_game(players["alice"], game_id, "AAAA")
        assert error.value.code == gs.BAD_REQUEST


class TestHistoryAndLeaderboard:
    def test_history_lists_finished_games_with_the_opponent(self, db, players, png, monkeypatch):
        scores = iter([("cat", 0.9, 0.9), ("cat", 0.4, 0.4)])
        monkeypatch.setattr(ml, "classify", lambda processed, prompt: next(scores))
        game_id = start_game(players)
        gs.submit_drawing(players["alice"], game_id, png())
        gs.submit_drawing(players["bob"], game_id, png())

        mine = gs.get_history(players["alice"])
        assert len(mine) == 1 and mine[0]["result"] == "win" and mine[0]["opponent_username"] == "bob"
        assert mine[0]["your_score"] > mine[0]["opponent_score"]
        assert gs.get_history(players["bob"])[0]["result"] == "loss"
        assert gs.get_history(players["carol"]) == []

    def test_unfinished_games_are_not_in_the_history(self, db, players):
        start_game(players)
        assert gs.get_history(players["alice"]) == []

    def test_leaderboard_ranks_by_wins_then_best_score(self, db, players):
        for name, wins, games, best in (("alice", 3, 4, 90.0), ("bob", 3, 6, 95.0), ("carol", 0, 0, 0.0)):
            db.profile(name).update(total_wins=wins, total_games=games, best_score=best)
        board = gs.get_leaderboard()
        assert [e["username"] for e in board] == ["bob", "alice"]  # tie on wins -> higher best score first
        assert [e["rank"] for e in board] == [1, 2]
        assert board[0]["win_rate"] == 50.0 and board[1]["win_rate"] == 75.0

    def test_leaderboard_limit(self, db, players):
        for name in players:
            db.profile(name).update(total_wins=1, total_games=1)
        assert len(gs.get_leaderboard(2)) == 2


# =================================================================================================
# HTTP layer
# =================================================================================================
class TestApi:
    def test_endpoints_require_a_token(self, client):
        assert client.post(f"{U}/room/create").status_code == 401
        assert client.get(f"{U}/history").status_code == 401
        assert client.get("/api/v1/leaderboard/top").status_code == 401
        bad = {"Authorization": "Bearer nope"}
        assert client.post(f"{U}/room/create", headers=bad).status_code == 401

    def test_full_match_over_http(self, client, db, players, png):
        a, b = db.headers("alice"), db.headers("bob")
        room = client.post(f"{U}/room/create", headers=a).json()
        joined = client.post(f"{U}/room/join", json={"room_code": room["room_code"]}, headers=b)
        assert joined.status_code == 200 and joined.json()["status"] == "active"

        body = {"game_id": room["game_id"], "drawing_data": png()}
        assert client.post(f"{U}/predict", json=body, headers=a).status_code == 200
        first = client.post(f"{U}/score", json=body, headers=a)
        assert first.status_code == 200 and first.json()["status"] == "active"
        second = client.post(f"{U}/score", json=body, headers=b)
        assert second.status_code == 200 and second.json()["status"] == "finished"

        view = client.get(f"{U}/room/id/{room['game_id']}", headers=a).json()
        assert view["player1_score"] is not None and view["player2_score"] is not None
        assert len(client.get(f"{U}/history", headers=a).json()) == 1
        assert len(client.get("/api/v1/leaderboard/top", headers=a).json()) == 2

    def test_service_errors_map_to_http_statuses(self, client, db, players, png):
        a = db.headers("alice")
        room = client.post(f"{U}/room/create", headers=a).json()
        assert client.post(f"{U}/room/join", json={"room_code": room["room_code"]}, headers=a).status_code == 409
        assert client.post(f"{U}/room/join", json={"room_code": "ZZZZZZ"}, headers=db.headers("bob")).status_code == 404
        assert client.get(f"{U}/room/id/{room['game_id']}", headers=db.headers("carol")).status_code == 404
        body = {"game_id": room["game_id"], "drawing_data": png()}
        assert client.post(f"{U}/score", json=body, headers=a).status_code == 409  # not started yet

    def test_input_validation(self, client, db, players):
        a = db.headers("alice")
        assert client.post(f"{U}/room/join", json={"room_code": "ab!"}, headers=a).status_code == 422
        assert client.post(f"{U}/room/join", json={}, headers=a).status_code == 422
        assert client.get(f"{U}/room/id/not-a-uuid", headers=a).status_code == 422
        assert client.post(f"{U}/score", json={"game_id": "x", "drawing_data": "y"}, headers=a).status_code == 422
        assert client.get("/api/v1/leaderboard/top?limit=0", headers=a).status_code == 422
        assert client.get(f"{U}/history?limit=1000", headers=a).status_code == 422

    def test_client_cannot_choose_the_player_or_the_prompt(self, client, db, players, png):
        a, c = db.headers("alice"), db.headers("carol")
        room = client.post(f"{U}/room/create", headers=a).json()
        client.post(f"{U}/room/join", json={"room_code": room["room_code"]}, headers=db.headers("bob"))
        body = {"game_id": room["game_id"], "drawing_data": png(),
                "player_id": players["alice"], "prompt": "cat", "time_taken": 0}
        assert client.post(f"{U}/score", json=body, headers=c).status_code == 404  # still carol, not alice

    def test_old_unauthenticated_routes_are_gone(self, client, players):
        assert client.get(f"{U}/room/ABC123").status_code in (404, 405)
        assert client.get(f"{U}/history/{players['alice']}").status_code in (404, 405)

    def test_rate_limit_on_room_creation(self, client, db, players, real_rate_limits):
        statuses = [client.post(f"{U}/room/create", headers=db.headers("alice")).status_code for _ in range(12)]
        assert statuses[:10] == [200] * 10 and 429 in statuses[10:]

    def test_oversized_body_is_refused(self, client, db, players):
        response = client.post(
            f"{U}/score", content=b"x", headers={**db.headers("alice"), "content-length": "99999999",
                                                 "content-type": "application/json"},
        )
        assert response.status_code == 413