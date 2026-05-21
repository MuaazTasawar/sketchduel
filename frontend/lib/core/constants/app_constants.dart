class AppConstants {
  static const String appName = 'SketchDuel';

  // FOR CHROME / WEB (you are here)
  static const String baseUrl = 'http://localhost:8000/api/v1';

  // FOR Android emulator use this instead:
  // static const String baseUrl = 'http://10.0.2.2:8000/api/v1';

  static const String supabaseUrl = 'https://erprzuconhstvqefcouj.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVycHJ6dWNvbmhzdHZxZWZjb3VqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzODQ2OTIsImV4cCI6MjA5NDk2MDY5Mn0.V2c2cYoCOotu_XcFAmuUkKZpOKNEARsTOzuRcO2imDQ';

  static const int drawingTimeSeconds = 60;
  static const int maxRoomCodeLength = 6;

  static const String createRoomEndpoint = '/game/room/create';
  static const String joinRoomEndpoint = '/game/room/join';
  static const String scoreEndpoint = '/game/score';
  static const String leaderboardEndpoint = '/leaderboard/top';
}