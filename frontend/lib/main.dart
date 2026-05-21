import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sketchduel_app/core/theme/app_theme.dart';
import 'package:sketchduel_app/core/utils/supabase_client.dart';
import 'package:sketchduel_app/features/auth/screens/login_screen.dart';
import 'package:sketchduel_app/features/auth/screens/register_screen.dart';
import 'package:sketchduel_app/features/game/screens/game_screen.dart';
import 'package:sketchduel_app/features/game/screens/lobby_screen.dart';
import 'package:sketchduel_app/features/game/screens/result_screen.dart';
import 'package:sketchduel_app/features/home/screens/home_screen.dart';
import 'package:sketchduel_app/features/leaderboard/screens/leaderboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseClientHelper.initialize();
  runApp(const SketchDuelApp());
}

final _router = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) {
    final isLoggedIn = SupabaseClientHelper.isLoggedIn;
    final onAuth = state.matchedLocation == '/login' ||
        state.matchedLocation == '/register';
    if (!isLoggedIn && !onAuth) return '/login';
    if (isLoggedIn && onAuth) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
    GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
    GoRoute(
      path: '/lobby',
      builder: (_, state) =>
          LobbyScreen(mode: state.uri.queryParameters['mode'] ?? 'create'),
    ),
    GoRoute(
      path: '/game',
      builder: (_, state) {
        final q = state.uri.queryParameters;
        return GameScreen(
          roomCode: q['roomCode'] ?? '',
          gameId: q['gameId'] ?? '',
          prompt: q['prompt'] ?? '',
          isPlayer1: q['isPlayer1'] == 'true',
        );
      },
    ),
    GoRoute(
      path: '/result',
      builder: (_, state) {
        final q = state.uri.queryParameters;
        return ResultScreen(
          gameId: q['gameId'] ?? '',
          winnerId: q['winnerId'] ?? '',
          p1Score: double.tryParse(q['p1Score'] ?? '0') ?? 0,
          p2Score: double.tryParse(q['p2Score'] ?? '0') ?? 0,
        );
      },
    ),
    GoRoute(path: '/leaderboard', builder: (_, __) => const LeaderboardScreen()),
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