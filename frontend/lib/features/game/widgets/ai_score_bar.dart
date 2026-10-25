import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:sketchduel_app/core/theme/app_theme.dart';

class AiScoreBar extends StatelessWidget {
  final double confidence;
  final String recognizedAs;
  final bool bluffDetected;
  final bool isVisible;

  const AiScoreBar({
    super.key,
    required this.confidence,
    required this.recognizedAs,
    required this.bluffDetected,
    this.isVisible = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    final color = bluffDetected ? AppTheme.secondary : AppTheme.accent;
    final label = bluffDetected ? '🎭 Bluff detected!' : '🤖 AI sees: $recognizedAs';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              )),
          const SizedBox(height: 10),
          LinearPercentIndicator(
            lineHeight: 10,
            percent: confidence.clamp(0.0, 1.0),
            backgroundColor: AppTheme.cardColor,
            progressColor: color,
            barRadius: const Radius.circular(5),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 6),
          Text(
            'Confidence: ${(confidence * 100).toStringAsFixed(1)}%',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ).animate().fadeIn().scale(begin: const Offset(0.9, 0.9));
  }
}