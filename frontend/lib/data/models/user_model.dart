class UserModel {
  final String id;

  /// Only present for your own profile; other players' e-mail addresses are never sent.
  final String? email;
  final String username;
  final int totalWins;
  final int totalGames;
  final double bestScore;

  const UserModel({
    required this.id,
    this.email,
    required this.username,
    this.totalWins = 0,
    this.totalGames = 0,
    this.bestScore = 0.0,
  });

  double get winRate => totalGames > 0 ? (totalWins / totalGames * 100) : 0.0;

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] as String,
        email: json['email'] as String?,
        username: json['username'] as String,
        totalWins: (json['total_wins'] as num?)?.toInt() ?? 0,
        totalGames: (json['total_games'] as num?)?.toInt() ?? 0,
        bestScore: (json['best_score'] as num?)?.toDouble() ?? 0.0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (email != null) 'email': email,
        'username': username,
        'total_wins': totalWins,
        'total_games': totalGames,
        'best_score': bestScore,
      };
}