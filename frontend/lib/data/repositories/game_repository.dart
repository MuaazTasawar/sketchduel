import 'package:sketchduel_app/data/datasources/api_datasource.dart';
import 'package:sketchduel_app/data/models/game_model.dart';

class GameRepository {
  final ApiDatasource _api = ApiDatasource();

  Future<Map<String, dynamic>> createRoom(String playerId, String token) async {
    final result = await _api.get(
      '/game/room/create?player_id=$playerId',
      token: token,
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<GameRoom> joinRoom(
      String roomCode, String playerId, String token) async {
    final data = await _api.post(
      '/game/room/join',
      {'room_code': roomCode, 'player_id': playerId},
      token: token,
    );
    return GameRoom.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<GameRoom> getRoom(String roomCode) async {
    final data = await _api.get('/game/room/$roomCode');
    return GameRoom.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<ScoreResult> submitDrawing({
    required String gameId,
    required String playerId,
    required String drawingBase64,
    required String prompt,
    required double timeTaken,
    required String token,
  }) async {
    final data = await _api.post(
      '/game/score',
      {
        'game_id': gameId,
        'player_id': playerId,
        'drawing_data': drawingBase64,
        'prompt': prompt,
        'time_taken': timeTaken,
      },
      token: token,
    );
    return ScoreResult.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<dynamic>> getLeaderboard() async {
    final result = await _api.get('/leaderboard/top');
    return List<dynamic>.from(result as List);
  }
}