import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sketchduel_app/core/constants/app_constants.dart';

/// Thrown at start-up when the Supabase settings were not provided with --dart-define.
class ConfigurationError implements Exception {
  const ConfigurationError(this.message);

  final String message;

  @override
  String toString() => message;
}

class SupabaseClientHelper {
  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    if (!AppConstants.isConfigured) {
      throw const ConfigurationError(
        'SUPABASE_URL and SUPABASE_ANON_KEY are not set.\n'
        'Copy frontend/env.example.json to env.json, fill it in, then run:\n'
        'flutter run -d chrome --dart-define-from-file=env.json',
      );
    }
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
  }

  static User? get currentUser => client.auth.currentUser;
  static bool get isLoggedIn => currentUser != null;
  static String? get userId => currentUser?.id;

  static Stream<AuthState> get authStateChanges =>
      client.auth.onAuthStateChange;

  /// The access token the API expects as `Authorization: Bearer <token>`.
  /// With [forceRefresh] it first asks Supabase for a fresh one (used after a 401).
  static Future<String?> accessToken({bool forceRefresh = false}) async {
    if (forceRefresh) {
      try {
        final response = await client.auth.refreshSession();
        return response.session?.accessToken;
      } catch (_) {
        return null;
      }
    }
    return client.auth.currentSession?.accessToken;
  }

  static Future<void> signOut() => client.auth.signOut();

  /// Realtime: get nudged when a game room row changes.
  ///
  /// Treat the payload only as a signal and re-read the room through the API: the API hides the
  /// opponent's score until the match is over, the raw row does not.
  static RealtimeChannel listenToRoom(
    String roomId,
    void Function(Map<String, dynamic>) onUpdate,
  ) {
    return client
        .channel('game_room_$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'game_rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: roomId,
          ),
          callback: (payload) => onUpdate(payload.newRecord),
        )
        .subscribe();
  }

  static Future<void> stopListening(RealtimeChannel channel) async {
    await client.removeChannel(channel);
  }
}