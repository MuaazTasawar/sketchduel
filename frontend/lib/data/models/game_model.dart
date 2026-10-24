import 'package:sketchduel_app/core/constants/app_constants.dart';

double? _asDouble(Object? value) => value is num ? value.toDouble() : null;

/// How a finished game ended for one player.
enum GameOutcome { win, loss, draw, pending }

/// Answer to "create a room".
class CreatedRoom {
  final String roomCode;
  final String gameId;
  final String prompt;

  const CreatedRoom({
    required this.roomCode,
    required this.gameId,
    required this.prompt,
  });

  factory CreatedRoom.fromJson(Map<String, dynamic> json) => CreatedRoom(
        roomCode: json['room_code'] as String,
        gameId: json['game_id'] as String,
        prompt: json['prompt'] as String,
      );
}

/// A game as the server shows it to one of its players.
///
/// The opponent's score is null until the game is finished.
class GameRoom {
  final String id;
  final String roomCode;
  final String prompt;
  final String status; // waiting | active | finished
  final String? player1Id;
  final String? player2Id;
  final double? player1Score;
  final double? player2Score;
  final String? winnerId;
  final bool isDraw;
  final bool isPlayer1;

  /// Seconds left to draw according to the SERVER clock (null unless the game is active).
  final double? secondsRemaining;
  final int timeLimitSeconds;
  final String? startedAt;
  final String? finishedAt;

  const GameRoom({
    required this.id,
    required this.roomCode,
    required this.prompt,
    required this.status,
    this.player1Id,
    this.player2Id,
    this.player1Score,
    this.player2Score,
    this.winnerId,
    this.isDraw = false,
    this.isPlayer1 = false,
    this.secondsRemaining,
    this.timeLimitSeconds = AppConstants.drawingTimeSeconds,
    this.startedAt,
    this.finishedAt,
  });

  bool get isFinished => status == 'finished';
  bool get isActive => status == 'active';
  bool get isWaiting => status == 'waiting';

  String? get opponentId => isPlayer1 ? player2Id : player1Id;
  double? get myScore => isPlayer1 ? player1Score : player2Score;
  double? get opponentScore => isPlayer1 ? player2Score : player1Score;

  GameOutcome outcomeFor(String? userId) {
    if (!isFinished) return GameOutcome.pending;
    if (isDraw || winnerId == null) return GameOutcome.draw;
    return winnerId == userId ? GameOutcome.win : GameOutcome.loss;
  }

  factory GameRoom.fromJson(Map<String, dynamic> json) => GameRoom(
        id: json['id'] as String,
        roomCode: json['room_code'] as String,
        prompt: json['prompt'] as String,
        status: json['status'] as String,
        player1Id: json['player1_id'] as String?,
        player2Id: json['player2_id'] as String?,
        player1Score: _asDouble(json['player1_score']),
        player2Score: _asDouble(json['player2_score']),
        winnerId: json['winner_id'] as String?,
        isDraw: json['is_draw'] == true,
        isPlayer1: json['is_player1'] == true,
        secondsRemaining: _asDouble(json['seconds_remaining']),
        timeLimitSeconds: (json['time_limit_seconds'] as num?)?.toInt() ??
            AppConstants.drawingTimeSeconds,
        startedAt: json['started_at'] as String?,
        finishedAt: json['finished_at'] as String?,
      );
}

/// Answer to "submit my drawing".
class ScoreResult {
  /// False when this player had already handed in a drawing (nothing was re-scored).
  final bool submitted;
  final double? score;
  final double baseScore;
  final double speedBonus;
  final double bluffBonus;
  final bool bluffDetected;
  final String recognizedAs;
  final double confidence;
  final double promptConfidence;
  final bool blank;
  final bool late;
  final double? timeTaken;
  final String? model;
  final String status; // active (waiting for the opponent) | finished
  final String? winnerId;
  final bool isDraw;
  final GameRoom room;

  const ScoreResult({
    this.submitted = true,
    this.score,
    this.baseScore = 0.0,
    this.speedBonus = 0.0,
    this.bluffBonus = 0.0,
    this.bluffDetected = false,
    this.recognizedAs = '',
    this.confidence = 0.0,
    this.promptConfidence = 0.0,
    this.blank = false,
    this.late = false,
    this.timeTaken,
    this.model,
    required this.status,
    this.winnerId,
    this.isDraw = false,
    required this.room,
  });

  double get scoreValue => score ?? 0.0;
  bool get isFinished => status == 'finished';

  /// Older name for [status].
  String get gameStatus => status;

  factory ScoreResult.fromJson(Map<String, dynamic> json) => ScoreResult(
        submitted: json['submitted'] != false,
        score: _asDouble(json['score']),
        baseScore: _asDouble(json['base_score']) ?? 0.0,
        speedBonus: _asDouble(json['speed_bonus']) ?? 0.0,
        bluffBonus: _asDouble(json['bluff_bonus']) ?? 0.0,
        bluffDetected: json['bluff_detected'] == true,
        recognizedAs: (json['recognized_as'] as String?) ?? '',
        confidence: _asDouble(json['confidence']) ?? 0.0,
        promptConfidence: _asDouble(json['prompt_confidence']) ?? 0.0,
        blank: json['blank'] == true,
        late: json['late'] == true,
        timeTaken: _asDouble(json['time_taken']),
        model: json['model'] as String?,
        status: json['status'] as String,
        winnerId: json['winner_id'] as String?,
        isDraw: json['is_draw'] == true,
        room: GameRoom.fromJson(Map<String, dynamic>.from(json['room'] as Map)),
      );
}

/// What the AI sees in the drawing right now (the live bar). Nothing is scored or stored.
class LivePrediction {
  final String recognizedAs;
  final double confidence;
  final double promptConfidence;
  final bool bluffDetected;

  /// True when the AI is confidently sure it is NOT the prompt (this is what earns the bluff bonus).
  final bool bluffEligible;
  final bool blank;
  final String model;
  final double? secondsRemaining;

  const LivePrediction({
    required this.recognizedAs,
    required this.confidence,
    required this.promptConfidence,
    required this.bluffDetected,
    required this.bluffEligible,
    required this.blank,
    required this.model,
    this.secondsRemaining,
  });

  factory LivePrediction.fromJson(Map<String, dynamic> json) => LivePrediction(
        recognizedAs: (json['recognized_as'] as String?) ?? '',
        confidence: _asDouble(json['confidence']) ?? 0.0,
        promptConfidence: _asDouble(json['prompt_confidence']) ?? 0.0,
        bluffDetected: json['bluff_detected'] == true,
        bluffEligible: json['bluff_eligible'] == true,
        blank: json['blank'] == true,
        model: (json['model'] as String?) ?? 'mock',
        secondsRemaining: _asDouble(json['seconds_remaining']),
      );
}

/// One finished game in a player's history.
class HistoryEntry {
  final String gameId;
  final String roomCode;
  final String prompt;
  final String result; // win | loss | draw
  final double? yourScore;
  final double? opponentScore;
  final String? opponentUsername;
  final String? finishedAt;

  const HistoryEntry({
    required this.gameId,
    required this.roomCode,
    required this.prompt,
    required this.result,
    this.yourScore,
    this.opponentScore,
    this.opponentUsername,
    this.finishedAt,
  });

  GameOutcome get outcome => switch (result) {
        'win' => GameOutcome.win,
        'loss' => GameOutcome.loss,
        'draw' => GameOutcome.draw,
        _ => GameOutcome.pending,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        gameId: json['game_id'] as String,
        roomCode: json['room_code'] as String,
        prompt: json['prompt'] as String,
        result: json['result'] as String,
        yourScore: _asDouble(json['your_score']),
        opponentScore: _asDouble(json['opponent_score']),
        opponentUsername: json['opponent_username'] as String?,
        finishedAt: json['finished_at'] as String?,
      );
}