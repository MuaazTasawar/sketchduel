import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:sketchduel_app/core/theme/app_theme.dart';

class PromptCard extends StatelessWidget {
  final String prompt;
  final int secondsLeft;
  final int totalSeconds;

  const PromptCard({
    super.key,
    required this.prompt,
    required this.secondsLeft,
    required this.totalSeconds,
  });

  Color get _timerColor {
    if (secondsLeft > 30) return AppTheme.accent;
    if (secondsLeft > 10) return Colors.orange;
    return AppTheme.secondary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Draw this:',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  prompt.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Text(
                '$secondsLeft',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: _timerColor,
                ),
              ).animate(key: ValueKey(secondsLeft)).scale(
                    begin: const Offset(1.2, 1.2),
                    end: const Offset(1.0, 1.0),
                    duration: 200.ms,
                  ),
              const Text('sec',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}