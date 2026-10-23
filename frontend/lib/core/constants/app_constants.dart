/// Compile-time configuration.
///
/// Values are injected with `--dart-define` / `--dart-define-from-file=env.json`:
///   flutter run -d chrome --dart-define-from-file=env.json
class AppConstants {
  static const String appName = 'SketchDuel';

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000/api/v1',
  );

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// True when the Supabase values were provided at build/run time.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// The server is authoritative for the match deadline; this only drives the UI timer.
  static const int drawingTimeSeconds = 60;
  static const int maxRoomCodeLength = 6;
  static const int livePreviewIntervalSeconds = 5;
  static const int roomPollIntervalSeconds = 3;

  // API endpoints (relative to baseUrl)
  static const String createRoomEndpoint = '/game/room/create';
  static const String joinRoomEndpoint = '/game/room/join';
  static const String roomByIdEndpoint = '/game/room/id';
  static const String scoreEndpoint = '/game/score';
  static const String predictEndpoint = '/game/predict';
  static const String historyEndpoint = '/game/history';
  static const String leaderboardEndpoint = '/leaderboard/top';
  static const String profileEndpoint = '/auth/profile';
}