import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sketchduel_app/core/theme/app_theme.dart';
import 'package:sketchduel_app/core/utils/supabase_client.dart';
import 'package:sketchduel_app/data/models/game_model.dart';
import 'package:sketchduel_app/features/auth/screens/login_screen.dart';
import 'package:sketchduel_app/features/auth/screens/register_screen.dart';
import 'package:sketchduel_app/features/game/screens/game_screen.dart';
import 'package:sketchduel_app/features/game/screens/lobby_screen.dart';
import 'package:sketchduel_app/features/game/screens/result_screen.dart';
import 'package:sketchduel_app/features/home/screens/home_screen.dart';
import 'package:sketchduel_app/features/leaderboard/screens/leaderboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SupabaseClientHelper.initialize();
  } catch (error) {
    // Most likely: the app was started without --dart-define-from-file=env.json
    runApp(StartupErrorApp(message: error.toString()));
    return;
  }
  runApp(const SketchDuelApp());
}

/// Re-runs the router's redirect whenever the signed-in state changes
/// (signing out, or a session that could not be refreshed).
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final _router = GoRouter(
  initialLocation: '/login',
  refreshListenable: _AuthRefresh(SupabaseClientHelper.authStateChanges),
  redirect: (context, state) {
    final isLoggedIn = SupabaseClientHelper.isLoggedIn;
    final onAuth =
        state.matchedLocation == '/login' ||
        state.matchedLocation == '/register';
    if (!isLoggedIn && !onAuth) return '/login';
    if (isLoggedIn && onAuth) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/lobby',
      builder: (context, state) =>
          LobbyScreen(mode: state.uri.queryParameters['mode'] ?? 'create'),
    ),
    GoRoute(
      path: '/game',
      redirect: (context, state) =>
          (state.uri.queryParameters['gameId'] ?? '').isEmpty ? '/home' : null,
      builder: (context, state) =>
          GameScreen(gameId: state.uri.queryParameters['gameId'] ?? ''),
    ),
    GoRoute(
      path: '/result',
      redirect: (context, state) =>
          (state.uri.queryParameters['gameId'] ?? '').isEmpty ? '/home' : null,
      builder: (context, state) {
        final extra = state.extra;
        return ResultScreen(
          gameId: state.uri.queryParameters['gameId'] ?? '',
          myResult: extra is ScoreResult ? extra : null,
        );
      },
    ),
    GoRoute(
      path: '/leaderboard',
      builder: (context, state) => const LeaderboardScreen(),
    ),
  ],
);

class SketchDuelApp extends StatelessWidget {
  const SketchDuelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SketchDuel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: _router,
    );
  }
}

/// Shown instead of the app when it cannot start (for example missing configuration).
class StartupErrorApp extends StatelessWidget {
  final String message;

  const StartupErrorApp({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SketchDuel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.settings_suggest_outlined,
                    size: 64,
                    color: AppTheme.secondary,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "SketchDuel can't start",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}