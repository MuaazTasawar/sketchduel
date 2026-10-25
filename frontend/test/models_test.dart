import 'package:flutter_test/flutter_test.dart';
import 'package:sketchduel_app/data/models/game_model.dart';
import 'package:sketchduel_app/data/models/user_model.dart';
import 'package:sketchduel_app/features/game/game_clock.dart';

import 'fixtures.dart';

void main() {
  group('CreatedRoom', () {
    test('parses the create-room answer', () {
      final room = CreatedRoom.fromJson(asMap(createRoomJson));
      expect(room.roomCode, 'TQXRMV');
      expect(room.gameId, gameId);
      expect(room.prompt, 'cloud');
    });
  });

  group('GameRoom', () {
    test('a waiting room has no opponent and no clock', () {
      final room = GameRoom.fromJson(asMap(roomWaitingJson));
      expect(room.isWaiting, isTrue);
      expect(room.isPlayer1, isTrue);
      expect(room.opponentId, isNull);
      expect(room.secondsRemaining, isNull);
      expect(room.outcomeFor(aliceId), GameOutcome.pending);
    });

    test(
      'joining gives the second player an active game with a 60 second clock',
      () {
        final room = GameRoom.fromJson(asMap(joinRoomJson));
        expect(room.isActive, isTrue);
        expect(room.isPlayer1, isFalse);
        expect(room.secondsRemaining, 60.0);
        expect(room.timeLimitSeconds, 60);
        expect(room.opponentId, aliceId);
      },
    );

    test('scores stay hidden while the game is running', () {
      final room = GameRoom.fromJson(asMap(roomActiveJson));
      expect(room.myScore, isNull);
      expect(room.opponentScore, isNull);
      expect(room.outcomeFor(aliceId), GameOutcome.pending);
    });

    test('a finished room shows both scores from the right point of view', () {
      final room = GameRoom.fromJson(asMap(roomFinishedJson));
      expect(room.isFinished, isTrue);
      expect(room.myScore, 79.29);
      expect(room.opponentScore, 61.92);
      expect(room.opponentId, bobId);
    });

    test('the same game looks mirrored for the other player', () {
      final bobsView = {...asMap(roomFinishedJson), 'is_player1': false};
      final room = GameRoom.fromJson(bobsView);
      expect(room.myScore, 61.92);
      expect(room.opponentScore, 79.29);
      expect(room.opponentId, aliceId);
    });

    test('outcome: win, loss and draw', () {
      final room = GameRoom.fromJson(asMap(roomFinishedJson));
      expect(room.outcomeFor(aliceId), GameOutcome.win);
      expect(room.outcomeFor(bobId), GameOutcome.loss);

      final draw = GameRoom.fromJson({
        ...asMap(roomFinishedJson),
        'winner_id': null,
        'is_draw': true,
      });
      expect(draw.outcomeFor(aliceId), GameOutcome.draw);
      expect(draw.outcomeFor(bobId), GameOutcome.draw);
    });

    test('missing optional fields fall back to safe defaults', () {
      final room = GameRoom.fromJson({
        'id': 'g',
        'room_code': 'ABCD12',
        'prompt': 'cat',
        'status': 'active',
      });
      expect(room.timeLimitSeconds, 60);
      expect(room.isDraw, isFalse);
      expect(room.isPlayer1, isFalse);
      expect(room.myScore, isNull);
    });

    test('scores sent as whole numbers still parse as doubles', () {
      final room = GameRoom.fromJson({
        ...asMap(roomFinishedJson),
        'player1_score': 70,
        'player2_score': 0,
      });
      expect(room.player1Score, 70.0);
      expect(room.player2Score, 0.0);
    });
  });

  group('ScoreResult', () {
    test('the first submission keeps the match open', () {
      final result = ScoreResult.fromJson(asMap(scoreFirstJson));
      expect(result.submitted, isTrue);
      expect(result.score, 79.29);
      expect(result.baseScore, 54.35);
      expect(result.speedBonus, 24.94);
      expect(result.bluffBonus, 0.0);
      expect(result.recognizedAs, 'cloud');
      expect(result.confidence, closeTo(0.9058, 0.0001));
      expect(result.isFinished, isFalse);
      expect(result.gameStatus, 'active');
      expect(result.room.myScore, 79.29);
      expect(result.room.opponentScore, isNull);
    });

    test('handing in again is reported as not submitted', () {
      final result = ScoreResult.fromJson(asMap(scoreResubmitJson));
      expect(result.submitted, isFalse);
      expect(result.score, isNull);
      expect(result.scoreValue, 0.0);
      expect(result.recognizedAs, '');
      expect(result.blank, isFalse);
    });

    test('the second submission finishes the match', () {
      final result = ScoreResult.fromJson(asMap(scoreFinishedJson));
      expect(result.isFinished, isTrue);
      expect(result.winnerId, aliceId);
      expect(result.isDraw, isFalse);
      expect(result.room.player1Score, 79.29);
      expect(result.room.player2Score, 61.92);
      expect(result.room.outcomeFor(bobId), GameOutcome.loss);
    });

    test('a blank, late or bluffing answer carries its flags', () {
      final base = asMap(scoreFirstJson);
      final blank = ScoreResult.fromJson({
        ...base,
        'blank': true,
        'score': 0.0,
      });
      expect(blank.blank, isTrue);
      final late = ScoreResult.fromJson({...base, 'late': true});
      expect(late.late, isTrue);
      final bluff = ScoreResult.fromJson({
        ...base,
        'bluff_detected': true,
        'bluff_bonus': 15.0,
      });
      expect(bluff.bluffDetected, isTrue);
      expect(bluff.bluffBonus, 15.0);
    });
  });

  group('LivePrediction', () {
    test('parses what the AI sees', () {
      final prediction = LivePrediction.fromJson(asMap(predictJson));
      expect(prediction.recognizedAs, 'cloud');
      expect(prediction.confidence, closeTo(0.8906, 0.0001));
      expect(prediction.blank, isFalse);
      expect(prediction.bluffEligible, isFalse);
      expect(prediction.model, 'mock');
      expect(prediction.secondsRemaining, 60.0);
    });

    test('an empty canvas is reported as blank', () {
      final prediction = LivePrediction.fromJson(asMap(predictBlankJson));
      expect(prediction.blank, isTrue);
      expect(prediction.recognizedAs, '');
      expect(prediction.confidence, 0.0);
    });
  });

  group('HistoryEntry', () {
    test('parses a finished game from the history', () {
      final entry = HistoryEntry.fromJson(
        Map<String, dynamic>.from(asList(historyJson).first as Map),
      );
      expect(entry.opponentUsername, 'bob');
      expect(entry.yourScore, 79.29);
      expect(entry.outcome, GameOutcome.win);
    });

    test('result strings map to outcomes', () {
      HistoryEntry entry(String result) => HistoryEntry(
        gameId: 'g',
        roomCode: 'ABCD12',
        prompt: 'cat',
        result: result,
      );
      expect(entry('loss').outcome, GameOutcome.loss);
      expect(entry('draw').outcome, GameOutcome.draw);
      expect(entry('???').outcome, GameOutcome.pending);
    });
  });

  group('UserModel', () {
    test('a public profile has no e-mail and a win rate', () {
      final user = UserModel.fromJson(asMap(profileJson));
      expect(user.username, 'alice');
      expect(user.email, isNull);
      expect(user.winRate, closeTo(66.67, 0.01));
      expect(user.toJson().containsKey('email'), isFalse);
    });

    test('your own profile keeps the e-mail', () {
      final user = UserModel.fromJson({
        ...asMap(profileJson),
        'email': 'a@b.c',
      });
      expect(user.email, 'a@b.c');
      expect(user.toJson()['email'], 'a@b.c');
    });

    test('no games means a 0 percent win rate, not a crash', () {
      expect(const UserModel(id: 'x', username: 'new').winRate, 0.0);
    });

    test('whole-number scores parse as doubles', () {
      final user = UserModel.fromJson({
        'id': 'a',
        'username': 'u',
        'best_score': 70,
      });
      expect(user.bestScore, 70.0);
    });
  });

  group('GameClock', () {
    var now = Duration.zero;
    GameClock make() => GameClock(limitSeconds: 60, uptime: () => now);

    setUp(() => now = Duration.zero);

    test('shows the full limit until the server has spoken', () {
      final clock = make();
      expect(clock.secondsLeft, 60);
      expect(clock.wholeSecondsLeft, 60);
      expect(clock.isSynced, isFalse);
      expect(clock.isExpired, isFalse);
    });

    test('a null sync is ignored', () {
      final clock = make()..sync(null);
      expect(clock.isSynced, isFalse);
    });

    test('counts down from the synced value', () {
      final clock = make()..sync(42.5);
      expect(clock.secondsLeft, 42.5);
      expect(clock.wholeSecondsLeft, 43);
      now += const Duration(seconds: 10);
      expect(clock.secondsLeft, 32.5);
    });

    test('each new sync cancels drift', () {
      final clock = make()..sync(42.5);
      now += const Duration(seconds: 10);
      clock.sync(20.0);
      expect(clock.secondsLeft, 20.0);
      now += const Duration(milliseconds: 1500);
      expect(clock.secondsLeft, 18.5);
    });

    test('never goes below zero and then reports expired', () {
      final clock = make()..sync(5.0);
      now += const Duration(seconds: 30);
      expect(clock.secondsLeft, 0.0);
      expect(clock.wholeSecondsLeft, 0);
      expect(clock.isExpired, isTrue);
    });

    test('never goes above the limit', () {
      expect((make()..sync(999)).secondsLeft, 60.0);
    });

    test('the server saying zero seconds left expires at once', () {
      expect((make()..sync(0.0)).isExpired, isTrue);
    });

    test('works when the stopwatch is already far from zero', () {
      now = const Duration(seconds: 100);
      final clock = make()..sync(5.0);
      now += const Duration(seconds: 4);
      expect(clock.secondsLeft, 1.0);
      expect(clock.isExpired, isFalse);
    });

    test('the default constructor uses a real stopwatch', () {
      expect(GameClock(limitSeconds: 60).secondsLeft, 60);
    });
  });
}