class UserModel {
  final String id;
  final String email;
  final String username;
  final int totalWins;
  final int totalGames;
  final double bestScore;

  UserModel({
    required this.id,
    required this.email,
    required this.username,
    this.totalWins = 0,
    this.totalGames = 0,
    this.bestScore = 0.0,
  });

  double get winRate =>
      totalGames > 0 ? (totalWins / totalGames * 100) : 0.0;

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'],
        email: json['email'],
        username: json['username'],
        totalWins: json['total_wins'] ?? 0,
        totalGames: json['total_games'] ?? 0,
        bestScore: (json['best_score'] ?? 0.0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'username': username,
        'total_wins': totalWins,
        'total_games': totalGames,
        'best_score': bestScore,
      };
}