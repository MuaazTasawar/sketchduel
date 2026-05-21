class AppConstants {
  static const String appName = 'SketchDuel';

  // Local development
  static const String baseUrl = 'http://10.0.2.2:8000/api/v1';
  // For web/iOS emulator use: 'http://localhost:8000/api/v1'
  // For production use: 'https://sketchduel-api.onrender.com/api/v1'

  // Supabase — replace with your actual values from supabase.com dashboard
  static const String supabaseUrl = 'https://your-project-id.supabase.co';
  static const String supabaseAnonKey = 'your-anon-public-key';

  static const int drawingTimeSeconds = 60;
  static const int maxRoomCodeLength = 6;

  static const String createRoomEndpoint = '/game/room/create';
  static const String joinRoomEndpoint = '/game/room/join';
  static const String scoreEndpoint = '/game/score';
  static const String leaderboardEndpoint = '/leaderboard/top';
}