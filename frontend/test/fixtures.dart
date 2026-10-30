// Real responses captured from the SketchDuel backend (the demo AI was in "mock" mode, with its
// guesses fixed so the story below is repeatable).
// Shared by the model and API tests so both are checked against what the server really sends.
import 'dart:convert';

const aliceId = '271364d4-522e-409b-a23b-876bc631417d';
const bobId = 'de884942-8902-4fff-be22-1ebad66cf01f';
const gameId = '0dccf0af-04f0-4328-981a-adf9b8ca6ab0';

Map<String, dynamic> asMap(String json) =>
    Map<String, dynamic>.from(jsonDecode(json) as Map);

List<dynamic> asList(String json) => jsonDecode(json) as List<dynamic>;

const createRoomJson =
    '''
{"room_code": "TQXRMV", "game_id": "$gameId", "prompt": "cloud"}
''';

const roomWaitingJson =
    '''
{"id": "$gameId", "room_code": "TQXRMV", "prompt": "cloud", "status": "waiting",
 "player1_id": "$aliceId", "player2_id": null, "player1_score": null, "player2_score": null,
 "winner_id": null, "is_draw": false, "is_player1": true, "seconds_remaining": null,
 "time_limit_seconds": 60, "started_at": null, "finished_at": null,
 "created_at": "2026-10-24T07:18:56.071278+00:00"}
''';

// Bob's view right after joining.
const joinRoomJson =
    '''
{"id": "$gameId", "room_code": "TQXRMV", "prompt": "cloud", "status": "active",
 "player1_id": "$aliceId", "player2_id": "$bobId", "player1_score": null, "player2_score": null,
 "winner_id": null, "is_draw": false, "is_player1": false, "seconds_remaining": 60.0,
 "time_limit_seconds": 60, "started_at": "2026-10-24T07:18:56.077368+00:00", "finished_at": null,
 "created_at": "2026-10-24T07:18:56.071278+00:00"}
''';

// Alice's view while the game is running.
const roomActiveJson =
    '''
{"id": "$gameId", "room_code": "TQXRMV", "prompt": "cloud", "status": "active",
 "player1_id": "$aliceId", "player2_id": "$bobId", "player1_score": null, "player2_score": null,
 "winner_id": null, "is_draw": false, "is_player1": true, "seconds_remaining": 60.0,
 "time_limit_seconds": 60, "started_at": "2026-10-24T07:18:56.077368+00:00", "finished_at": null,
 "created_at": "2026-10-24T07:18:56.071278+00:00"}
''';

// Alice's view of the finished match: she won 79.29 to 61.92.
const roomFinishedJson =
    '''
{"id": "$gameId", "room_code": "TQXRMV", "prompt": "cloud", "status": "finished",
 "player1_id": "$aliceId", "player2_id": "$bobId", "player1_score": 79.29, "player2_score": 61.92,
 "winner_id": "$aliceId", "is_draw": false, "is_player1": true, "seconds_remaining": null,
 "time_limit_seconds": 60, "started_at": "2026-10-24T07:18:56.077368+00:00",
 "finished_at": "2026-10-24T07:18:56.367546+00:00", "created_at": "2026-10-24T07:18:56.071278+00:00"}
''';

// What the AI sees while Alice draws: it reads her drawing as the prompt (a cloud).
const predictJson = '''
{"recognized_as": "cloud", "confidence": 0.9058, "prompt_confidence": 0.9058, "matches_prompt": true, "blank": false, "model": "mock", "seconds_remaining": 60.0}
''';

// Nothing drawn yet.
const predictBlankJson = '''
{"recognized_as": "", "confidence": 0.0, "prompt_confidence": 0.0, "matches_prompt": false, "blank": true, "model": "mock", "seconds_remaining": 59.9}
''';

// Alice hands in first. The AI reads her drawing as a dog (74% sure) but only 15% sure it is the
// prompt (a cloud), so she scores little. The match is still active and Bob's score is hidden.
const scoreFirstJson =
    '''
{"submitted": true, "score": 15.22, "accuracy_score": 10.66, "speed_bonus": 4.56, "matched": false, "recognized_as": "dog", "confidence": 0.74, "prompt_confidence": 0.1523, "blank": false, "late": false, "time_taken": 0.1, "model": "mock", "status": "active", "winner_id": null, "is_draw": false, "room": {"id": "$gameId", "room_code": "TQXRMV", "prompt": "cloud", "status": "active", "player1_id": "$aliceId", "player2_id": "$bobId", "player1_score": 15.22, "player2_score": null, "winner_id": null, "is_draw": false, "is_player1": true, "seconds_remaining": 59.9, "time_limit_seconds": 60, "started_at": "2026-10-26T22:32:45.040072+00:00", "finished_at": null, "created_at": "2026-10-26T22:32:45.036338+00:00"}}
''';

// Alice tries to hand in a second time: nothing is re-scored.
const scoreResubmitJson =
    '''
{"submitted": false, "score": null, "accuracy_score": null, "speed_bonus": null, "matched": null, "recognized_as": null, "confidence": null, "prompt_confidence": null, "blank": null, "late": false, "time_taken": null, "model": null, "status": "active", "winner_id": null, "is_draw": false, "room": {"id": "$gameId", "room_code": "TQXRMV", "prompt": "cloud", "status": "active", "player1_id": "$aliceId", "player2_id": "$bobId", "player1_score": 15.22, "player2_score": null, "winner_id": null, "is_draw": false, "is_player1": true, "seconds_remaining": 59.9, "time_limit_seconds": 60, "started_at": "2026-10-26T22:32:45.040072+00:00", "finished_at": null, "created_at": "2026-10-26T22:32:45.036338+00:00"}}
''';

// Bob hands in second and finishes the match (Bob's view). The AI is 62% sure his drawing is a
// cloud, so he wins 61.65 to 15.22.
const scoreFinishedJson =
    '''
{"submitted": true, "score": 61.65, "accuracy_score": 43.18, "speed_bonus": 18.47, "matched": true, "recognized_as": "cloud", "confidence": 0.6169, "prompt_confidence": 0.6169, "blank": false, "late": false, "time_taken": 0.12, "model": "mock", "status": "finished", "winner_id": "$bobId", "is_draw": false, "room": {"id": "$gameId", "room_code": "TQXRMV", "prompt": "cloud", "status": "finished", "player1_id": "$aliceId", "player2_id": "$bobId", "player1_score": 15.22, "player2_score": 61.65, "winner_id": "$bobId", "is_draw": false, "is_player1": false, "seconds_remaining": null, "time_limit_seconds": 60, "started_at": "2026-10-26T22:32:45.040072+00:00", "finished_at": "2026-10-26T22:32:45.174150+00:00", "created_at": "2026-10-26T22:32:45.036338+00:00"}}
''';

const historyJson =
    '''
[{"game_id": "$gameId", "room_code": "TQXRMV", "prompt": "cloud", "result": "win",
  "your_score": 79.29, "opponent_score": 61.92, "opponent_username": "bob",
  "finished_at": "2026-10-24T07:18:56.367546+00:00"}]
''';

const leaderboardJson = '''
[{"rank": 1, "username": "alice", "total_wins": 1, "total_games": 1, "win_rate": 100.0, "best_score": 79.29},
 {"rank": 2, "username": "bob", "total_wins": 0, "total_games": 1, "win_rate": 0.0, "best_score": 61.92}]
''';

const profileJson =
    '''
{"id": "$aliceId", "username": "alice", "total_wins": 2, "total_games": 3, "best_score": 70.5}
''';

const err404Json = '{"detail": "Room not found"}';
const err409Json =
    '{"detail": "This room is full or the game already started"}';

const err422Json = '''
{"detail": [{"type": "string_too_short", "loc": ["body", "room_code"],
  "msg": "String should have at least 4 characters", "input": "AB!", "ctx": {"min_length": 4}}]}
''';
