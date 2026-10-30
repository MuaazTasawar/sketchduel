import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:sketchduel_app/core/theme/app_theme.dart';
import 'package:sketchduel_app/core/utils/supabase_client.dart';
import 'package:sketchduel_app/data/datasources/api_datasource.dart';
import 'package:sketchduel_app/data/models/game_model.dart';
import 'package:sketchduel_app/data/repositories/game_repository.dart';

/// Shows how the match ended.
///
/// The scores come from the server (so they can never be swapped), keyed by the game id.
/// [myResult] is optional: when we arrive straight from the game screen it also shows what the
/// AI saw in our drawing and how the points were earned.
class ResultScreen extends StatefulWidget {
  final String gameId;
  final ScoreResult? myResult;

  const ResultScreen({super.key, required this.gameId, this.myResult});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final _repo = GameRepository();

  GameRoom? _room;
  String? _error;
  String? _opponentName;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final room = await _repo.getRoom(widget.gameId);
      if (!mounted) return;
      setState(() {
        _room = room;
        _error = null;
      });
      if (room.isFinished) {
        _poller?.cancel();
        _poller = null;
        _loadOpponentName(room);
      } else {
        // The opponent is still drawing: keep checking until the match is over.
        _poller ??= Timer.periodic(const Duration(seconds: 2), (_) => _load());
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_room == null) setState(() => _error = e.message);
    }
  }

  Future<void> _loadOpponentName(GameRoom room) async {
    final opponentId = room.opponentId;
    if (opponentId == null || _opponentName != null) return;
    try {
      final profile = await _repo.getProfile(opponentId);
      if (mounted) setState(() => _opponentName = profile.username);
    } catch (_) {
      // "Opponent" is a fine label
    }
  }

  void _retry() {
    setState(() => _error = null);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(24), child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    final room = _room;
    if (room == null) {
      if (_error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 56,
                color: AppTheme.secondary,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: _retry, child: const Text('Try again')),
              TextButton(
                onPressed: () => context.go('/home'),
                child: const Text('Back to home'),
              ),
            ],
          ),
        );
      }
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (!room.isFinished) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.primary),
            SizedBox(height: 16),
            Text(
              'Waiting for your opponent to finish...',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    final outcome = room.outcomeFor(SupabaseClientHelper.userId);
    final String title;
    final Color color;
    switch (outcome) {
      case GameOutcome.win:
        title = '🏆 You Win!';
        color = AppTheme.accent;
      case GameOutcome.loss:
        title = '😅 You Lose';
        color = AppTheme.secondary;
      case GameOutcome.draw:
      case GameOutcome.pending:
        title = "🤝 It's a Draw!";
        color = AppTheme.primary;
    }

    final mine = widget.myResult;

    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ).animate().scale(delay: 200.ms).fadeIn(),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ScoreCard(
                  label: 'You',
                  score: room.myScore ?? 0,
                  highlight: outcome == GameOutcome.win,
                ),
                _ScoreCard(
                  label: _opponentName ?? 'Opponent',
                  score: room.opponentScore ?? 0,
                  highlight: outcome == GameOutcome.loss,
                ),
              ],
            ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.3),
            if (mine != null && mine.submitted) ...[
              const SizedBox(height: 24),
              _Breakdown(
                result: mine,
                prompt: room.prompt,
              ).animate().fadeIn(delay: 500.ms),
            ],
            const SizedBox(height: 40),
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
              child: const Text(
                'View Leaderboard',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ).animate().fadeIn(delay: 700.ms),
          ],
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
              ? AppTheme.accent.withValues(alpha: 0.5)
              : AppTheme.surface,
          width: highlight ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
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

/// What the AI saw in your drawing and where your points came from.
class _Breakdown extends StatelessWidget {
  final ScoreResult result;
  final String prompt;

  const _Breakdown({required this.result, required this.prompt});

  @override
  Widget build(BuildContext context) {
    final match = (result.promptConfidence * 100).round();
    final String headline;
    if (result.blank) {
      headline = 'Your canvas was empty.';
    } else if (result.late) {
      headline = 'You handed in too late.';
    } else if (result.matched) {
      headline = 'The AI saw "$prompt" ($match% sure). Nice drawing!';
    } else {
      headline =
          'The AI saw "${result.recognizedAs}" instead of "$prompt" '
          '($match% match).';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(
            headline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(
                label: 'Accuracy',
                value: '+${result.accuracyScore.toStringAsFixed(1)}',
                color: AppTheme.primary,
              ),
              _Pill(
                label: 'Speed',
                value: '+${result.speedBonus.toStringAsFixed(1)}',
                color: AppTheme.accent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Pill({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}