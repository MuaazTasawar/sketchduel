class GameRoom {
  final String id;
  final String roomCode;
  final String prompt;
  final String status;
  final String? player1Id;
  final String? player2Id;
  final double? player1Score;
  final double? player2Score;
  final String? winnerId;

  GameRoom({
    required this.id,
    required this.roomCode,
    required this.prompt,
    required this.status,
    this.player1Id,
    this.player2Id,
    this.player1Score,
    this.player2Score,
    this.winnerId,
  });

  bool get isFinished => status == 'finished';
  bool get isActive => status == 'active';
  bool get isWaiting => status == 'waiting';

  factory GameRoom.fromJson(Map<String, dynamic> json) => GameRoom(
        id: json['id'],
        roomCode: json['room_code'],
        prompt: json['prompt'],
        status: json['status'],
        player1Id: json['player1_id'],
        player2Id: json['player2_id'],
        player1Score: json['player1_score']?.toDouble(),
        player2Score: json['player2_score']?.toDouble(),
        winnerId: json['winner_id'],
      );
}

class ScoreResult {
  final double score;
  final double baseScore;
  final double speedBonus;
  final double bluffBonus;
  final bool bluffDetected;
  final String recognizedAs;
  final double confidence;
  final String gameStatus;
  final String? winnerId;

  ScoreResult({
    required this.score,
    required this.baseScore,
    required this.speedBonus,
    required this.bluffBonus,
    required this.bluffDetected,
    required this.recognizedAs,
    required this.confidence,
    required this.gameStatus,
    this.winnerId,
  });

  factory ScoreResult.fromJson(Map<String, dynamic> json) => ScoreResult(
        score: (json['score'] ?? 0.0).toDouble(),
        baseScore: (json['base_score'] ?? 0.0).toDouble(),
        speedBonus: (json['speed_bonus'] ?? 0.0).toDouble(),
        bluffBonus: (json['bluff_bonus'] ?? 0.0).toDouble(),
        bluffDetected: json['bluff_detected'] ?? false,
        recognizedAs: json['recognized_as'] ?? '',
        confidence: (json['confidence'] ?? 0.0).toDouble(),
        gameStatus: json['status'] ?? 'waiting_for_opponent',
        winnerId: json['winner_id'],
      );
}