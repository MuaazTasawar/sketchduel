import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sketchduel_app/core/constants/app_constants.dart';
import 'package:sketchduel_app/core/theme/app_theme.dart';
import 'package:sketchduel_app/core/utils/supabase_client.dart';
import 'package:sketchduel_app/data/models/game_model.dart';
import 'package:sketchduel_app/data/repositories/game_repository.dart';
import 'package:sketchduel_app/features/game/widgets/ai_score_bar.dart';
import 'package:sketchduel_app/features/game/widgets/drawing_canvas.dart';
import 'package:sketchduel_app/features/game/widgets/prompt_card.dart';

class GameScreen extends StatefulWidget {
  final String roomCode;
  final String gameId;
  final String prompt;
  final bool isPlayer1;

  const GameScreen({
    super.key,
    required this.roomCode,
    required this.gameId,
    required this.prompt,
    required this.isPlayer1,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final _canvasKey = GlobalKey();
  final _repo = GameRepository();
  late Timer _timer;
  int _secondsLeft = AppConstants.drawingTimeSeconds;
  bool _submitted = false;
  bool _drawing = false;
  // _scoreResult removed — result is handled via navigation
  double _liveConfidence = 0.0;
  String _liveLabel = '';
  bool _bluff = false;

  String get _token =>
      SupabaseClientHelper.client.auth.currentSession?.accessToken ?? '';
  String get _userId => SupabaseClientHelper.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _startTimer();
    _listenForResults();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 0) {
        t.cancel();
        if (!_submitted) _submitDrawing();
      } else {
        setState(() => _secondsLeft--);
        // Simulate live AI preview every 5 seconds while drawing
        if (_drawing && _secondsLeft % 5 == 0) _updateLiveScore();
      }
    });
  }

  void _listenForResults() {
    SupabaseClientHelper.listenToRoom(widget.gameId, (room) {
      if (room['status'] == 'finished' && mounted) {
        context.go(
          '/result?gameId=${widget.gameId}'
          '&winnerId=${room['winner_id'] ?? ''}'
          '&p1Score=${room['player1_score'] ?? 0}'
          '&p2Score=${room['player2_score'] ?? 0}',
        );
      }
    });
  }

  Future<void> _updateLiveScore() async {
    // Lightweight live preview — show what AI currently thinks
    try {
      final canvasState =
          _canvasKey.currentWidget != null
              ? (_canvasKey.currentContext
                      ?.findAncestorStateOfType<DrawingCanvasState>())
              : null;
      // In production: run lightweight inference here
      // For now, simulate with random values
      setState(() {
        _liveConfidence = 0.3 + (60 - _secondsLeft) / 60 * 0.5;
        _liveLabel = widget.prompt;
        _bluff = _liveConfidence < 0.4;
      });
    } catch (_) {}
  }

  Future<void> _submitDrawing() async {
    if (_submitted) return;
    setState(() => _submitted = true);
    _timer.cancel();

    try {
      final canvasState = _canvasKey.currentContext
          ?.findAncestorStateOfType<DrawingCanvasState>();
      final base64 = await canvasState?.toBase64() ?? '';

      final timeTaken =
          (AppConstants.drawingTimeSeconds - _secondsLeft).toDouble();

      final result = await _repo.submitDrawing(
        gameId: widget.gameId,
        playerId: _userId,
        drawingBase64: base64,
        prompt: widget.prompt,
        timeTaken: timeTaken,
        token: _token,
      );

      if (result.gameStatus == 'finished' && mounted) {
        context.go(
          '/result?gameId=${widget.gameId}'
          '&winnerId=${result.winnerId ?? ''}'
          '&myScore=${result.score}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: PromptCard(
                prompt: widget.prompt,
                secondsLeft: _secondsLeft,
                totalSeconds: AppConstants.drawingTimeSeconds,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: DrawingCanvas(
                    canvasKey: _canvasKey,
                    onDrawingStarted: () => setState(() => _drawing = true),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  AiScoreBar(
                    confidence: _liveConfidence,
                    recognizedAs: _liveLabel,
                    bluffDetected: _bluff,
                    isVisible: _drawing && !_submitted,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final state = _canvasKey.currentContext
                                ?.findAncestorStateOfType<DrawingCanvasState>();
                            state?.clear();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Clear'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.textSecondary,
                            side: const BorderSide(color: AppTheme.surface),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _submitted ? null : _submitDrawing,
                          child: Text(_submitted
                              ? 'Waiting for opponent...'
                              : 'Submit Drawing'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}