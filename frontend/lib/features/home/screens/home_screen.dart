import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:sketchduel_app/core/theme/app_theme.dart';
import 'package:sketchduel_app/core/utils/supabase_client.dart';
import 'package:sketchduel_app/data/models/user_model.dart';
import 'package:sketchduel_app/data/repositories/game_repository.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repo = GameRepository();
  UserModel? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final id = SupabaseClientHelper.userId;
    if (id == null) return;
    try {
      final profile = await _repo.getProfile(id);
      if (mounted) setState(() => _profile = profile);
    } catch (_) {
      // the e-mail name is shown instead
    }
  }

  String get _displayName {
    final username = _profile?.username;
    if (username != null && username.isNotEmpty) return username;
    return SupabaseClientHelper.currentUser?.email?.split('@').first ??
        'Sketcher';
  }

  Future<void> _signOut() async {
    await SupabaseClientHelper.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Welcome back,',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          _displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        if (profile != null && profile.totalGames > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${profile.totalWins} wins · ${profile.totalGames} games',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _signOut,
                    icon: const Icon(
                      Icons.logout,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ).animate().fadeIn(),
              const SizedBox(height: 48),
              _BigButton(
                label: 'Create Room',
                subtitle: 'Start a new game and invite a friend',
                icon: Icons.add_circle_outline,
                color: AppTheme.primary,
                onTap: () => context.go('/lobby?mode=create'),
              ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.3),
              const SizedBox(height: 16),
              _BigButton(
                label: 'Join Room',
                subtitle: "Enter a code to join a friend's game",
                icon: Icons.login,
                color: AppTheme.secondary,
                onTap: () => context.go('/lobby?mode=join'),
              ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.3),
              const SizedBox(height: 16),
              _BigButton(
                label: 'Leaderboard',
                subtitle: 'See the best sketchers worldwide',
                icon: Icons.leaderboard,
                color: AppTheme.accent,
                onTap: () => context.go('/leaderboard'),
              ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.3),
            ],
          ),
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _BigButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 16),
          ],
        ),
      ),
    );
  }
}