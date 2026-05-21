import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:sketchduel_app/core/theme/app_theme.dart';
import 'package:sketchduel_app/core/utils/supabase_client.dart';

class ResultScreen extends StatelessWidget {
  final String gameId;
  final String winnerId;
  final double p1Score;
  final double p2Score;

  const ResultScreen({
    super.key,
    required this.gameId,
    required this.winnerId,
    required this.p1Score,
    required this.p2Score,
  });

  @override
  Widget build(BuildContext context) {
    final myId = SupabaseClientHelper.currentUser?.id ?? '';
    final iWon = winnerId == myId;
    final myScore = iWon ? p1Score : p2Score;
    final oppScore = iWon ? p2Score : p1Score;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                iWon ? '🏆 You Win!' : '😅 You Lose',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  color: iWon ? AppTheme.accent : AppTheme.secondary,
                ),
              ).animate().scale(delay: 200.ms).fadeIn(),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ScoreCard(
                    label: 'Your Score',
                    score: myScore,
                    highlight: iWon,
                  ),
                  _ScoreCard(
                    label: 'Opponent',
                    score: oppScore,
                    highlight: !iWon,
                  ),
                ],
              ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.3),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Play Again'),
                ),
              ).animate().fadeIn(delay: 600.ms),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/leaderboard'),
                child: const Text('View Leaderboard',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ).animate().fadeIn(delay: 700.ms),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final String label;
  final double score;
  final bool highlight;

  const _ScoreCard({
    required this.label,
    required this.score,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlight
              ? AppTheme.accent.withOpacity(0.5)
              : AppTheme.surface,
          width: highlight ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          Text(
            score.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: highlight ? AppTheme.accent : AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}