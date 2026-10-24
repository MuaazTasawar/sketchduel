import 'package:sketchduel_app/core/constants/app_constants.dart';
import 'package:sketchduel_app/core/utils/supabase_client.dart';
import 'package:sketchduel_app/data/datasources/api_datasource.dart';
import 'package:sketchduel_app/data/models/game_model.dart';
import 'package:sketchduel_app/data/models/user_model.dart';

/// Everything the game screens ask the server.
///
/// The signed-in player is identified by the access token the datasource attaches to every
/// request. Nothing here sends a player id, a prompt or a time: the server knows those.
/// Errors surface as [ApiException] (its message is ready to show to the player).
class GameRepository {
  GameRepository({ApiDatasource? api})
      : _api = api ??
            ApiDatasource(tokenProvider: SupabaseClientHelper.accessToken);

  final ApiDatasource _api;

  Future<CreatedRoom> createRoom() async {
    final data = await _api.post(AppConstants.createRoomEndpoint, {});
    return CreatedRoom.fromJson(data);
  }

  Future<GameRoom> joinRoom(String roomCode) async {
    final data = await _api.post(AppConstants.joinRoomEndpoint, {
      'room_code': roomCode.trim().toUpperCase(),
    });
    return GameRoom.fromJson(data);
  }

  Future<GameRoom> getRoom(String gameId) async {
    final data = await _api.get('${AppConstants.roomByIdEndpoint}/$gameId');
    return GameRoom.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<ScoreResult> submitDrawing({
    required String gameId,
    required String drawingBase64,
  }) async {
    final data = await _api.post(AppConstants.scoreEndpoint, {
      'game_id': gameId,
      'drawing_data': drawingBase64,
    });
    return ScoreResult.fromJson(data);
  }

  /// What does the AI see right now? (the live bar)
  Future<LivePrediction> predict({
    required String gameId,
    required String drawingBase64,
  }) async {
    final data = await _api.post(
      AppConstants.predictEndpoint,
      {'game_id': gameId, 'drawing_data': drawingBase64},
      timeout: const Duration(seconds: 15),
    );
    return LivePrediction.fromJson(data);
  }

  Future<List<HistoryEntry>> getHistory({int limit = 20}) async {
    final data = await _api.get(
      AppConstants.historyEndpoint,
      query: {'limit': '$limit'},
    );
    return (data as List)
        .map((e) => HistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Raw leaderboard rows (rank, username, total_wins, total_games, win_rate, best_score).
  Future<List<dynamic>> getLeaderboard({int limit = 20}) async {
    final data = await _api.get(
      AppConstants.leaderboardEndpoint,
      query: {'limit': '$limit'},
    );
    return List<dynamic>.from(data as List);
  }

  Future<UserModel> getProfile(String userId) async {
    final data = await _api.get('${AppConstants.profileEndpoint}/$userId');
    return UserModel.fromJson(Map<String, dynamic>.from(data as Map));
  }
}