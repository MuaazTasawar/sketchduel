import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:sketchduel_app/core/theme/app_theme.dart';

/// The live "what does the AI see?" bar.
///
/// The bar shows how sure the AI is that your drawing is the PROMPT (that is what your score is
/// made of). The label tells you what the AI currently thinks it is looking at.
class AiScoreBar extends StatelessWidget {
  /// How sure the AI is that the drawing is the prompt (0..1).
  final double promptConfidence;

  /// The AI's best guess.
  final String recognizedAs;

  /// Whether that best guess is the prompt.
  final bool matchesPrompt;
  final bool isVisible;

  const AiScoreBar({
    super.key,
    required this.promptConfidence,
    required this.recognizedAs,
    required this.matchesPrompt,
    this.isVisible = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    final color = matchesPrompt ? AppTheme.accent : AppTheme.secondary;
    final label = matchesPrompt
        ? '\u2705 AI sees: $recognizedAs'
        : '\u{1F914} AI sees: $recognizedAs';
    final fraction = promptConfidence.clamp(0.0, 1.0);
    final percent = (fraction * 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The label takes the free space and is cut with "..." if it is too long.
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$percent%',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearPercentIndicator(
            lineHeight: 10,
            percent: fraction,
            backgroundColor: AppTheme.surface,
            progressColor: color,
            barRadius: const Radius.circular(5),
            padding: EdgeInsets.zero,
            animation: false,
          ),
          const SizedBox(height: 6),
          const Text(
            'Match with the prompt',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    ).animate().fadeIn().scale(begin: const Offset(0.95, 0.95));
  }
}
