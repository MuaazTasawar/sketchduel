import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sketchduel_app/core/constants/app_constants.dart';
import 'package:sketchduel_app/core/theme/app_theme.dart';
import 'package:sketchduel_app/core/utils/supabase_client.dart';
import 'package:sketchduel_app/data/datasources/api_datasource.dart';
import 'package:sketchduel_app/data/models/game_model.dart';
import 'package:sketchduel_app/data/repositories/game_repository.dart';
import 'package:sketchduel_app/features/game/game_clock.dart';
import 'package:sketchduel_app/features/game/widgets/ai_score_bar.dart';
import 'package:sketchduel_app/features/game/widgets/drawing_canvas.dart';
import 'package:sketchduel_app/features/game/widgets/prompt_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The drawing round.
///
/// The server owns the game: it tells us the prompt, how many seconds are left and who won.
/// This screen only needs the game id, so reloading the page in the middle of a round simply
/// picks the game up again (the drawing itself is lost, the clock is not).
class GameScreen extends StatefulWidget {
  final String gameId;

  const GameScreen({super.key, required this.gameId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final _repo = GameRepository();
  final _canvas = DrawingController();
  final _clock = GameClock(limitSeconds: AppConstants.drawingTimeSeconds);

  GameRoom? _room;
  String? _loadError;

  bool _submitting = false;
  bool _handedIn = false; // our drawing is with the server
  // The breakdown of our score, shown on the result screen.
  ScoreResult? _myResult;
  LivePrediction? _prediction;

  bool _predicting = false;
  bool _polling = false;
  bool _leaving = false;
  bool _hadInk = false;
  DateTime _nextAutoSubmit = DateTime.fromMillisecondsSinceEpoch(0);

  Timer? _ticker;
  Timer? _poller;
  Timer? _previewer;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _canvas.addListener(_onCanvasChanged);
    _load();
  }

  @override
  void dispose() {
    _stopBackgroundWork();
    _canvas.removeListener(_onCanvasChanged);
    _canvas.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ loading and syncing
  Future<void> _load() async {
    try {
      final room = await _repo.getRoom(widget.gameId);
      if (!mounted) return;
      setState(() => _loadError = null);
      _applyRoom(room);
      // A game that is already finished goes straight to the result screen.
      if (!_leaving) {
        _startBackgroundWork();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e.message);
    }
  }

  void _retry() {
    setState(() => _loadError = null);
    _load();
  }

  void _applyRoom(GameRoom room) {
    if (!mounted) return;
    setState(() {
      _room = room;
      if (room.myScore != null) _handedIn = true;
    });
    _clock.sync(room.secondsRemaining);
    if (room.isFinished) _goToResult();
  }

  void _startBackgroundWork() {
    _ticker ??= Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _tick(),
    );
    _poller ??= Timer.periodic(
      const Duration(seconds: AppConstants.roomPollIntervalSeconds),
      (_) => _poll(),
    );
    _previewer ??= Timer.periodic(
      const Duration(seconds: AppConstants.livePreviewIntervalSeconds),
      (_) => _updatePreview(),
    );
    _channel ??= _subscribe();
  }

  RealtimeChannel? _subscribe() {
    try {
      // Realtime is only a nudge ("something changed"); the answer always comes from the API.
      return SupabaseClientHelper.listenToRoom(widget.gameId, (_) => _poll());
    } catch (_) {
      return null; // polling alone is enough
    }
  }

  void _stopBackgroundWork() {
    _ticker?.cancel();
    _poller?.cancel();
    _previewer?.cancel();
    _ticker = null;
    _poller = null;
    _previewer = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(SupabaseClientHelper.stopListening(channel));
  }

  void _tick() {
    if (!mounted || _leaving) return;
    setState(() {}); // redraw the countdown

    final room = _room;
    if (room == null || !room.isActive) return;

    // Time is up: hand in whatever is on the canvas (retrying a few seconds apart if it fails).
    if (_clock.isExpired &&
        !_handedIn &&
        !_submitting &&
        DateTime.now().isAfter(_nextAutoSubmit)) {
      _nextAutoSubmit = DateTime.now().add(const Duration(seconds: 3));
      _submit();
    }
  }

  Future<void> _poll() async {
    if (_polling || !mounted || _leaving) return;
    _polling = true;
    try {
      _applyRoom(await _repo.getRoom(widget.gameId));
    } on ApiException catch (_) {
      // a network blip: the next poll tries again
    } finally {
      _polling = false;
    }
  }

  void _onCanvasChanged() {
    final hasInk = _canvas.hasInk;
    if (hasInk != _hadInk) {
      _hadInk = hasInk;
      if (mounted) setState(() {});
    }
  }

  // ------------------------------------------------------------------ live AI bar
  Future<void> _updatePreview() async {
    final room = _room;
    if (_predicting ||
        _handedIn ||
        _submitting ||
        _leaving ||
        room == null ||
        !room.isActive ||
        !_canvas.hasInk ||
        _clock.isExpired) {
      return;
    }
    _predicting = true;
    try {
      final drawing = await _canvas.toBase64();
      if (drawing.isEmpty) return;
      final prediction = await _repo.predict(
        gameId: widget.gameId,
        drawingBase64: drawing,
      );
      if (!mounted || _handedIn) return;
      setState(() => _prediction = prediction.blank ? null : prediction);
    } on ApiException catch (_) {
      // the live bar is a nicety: stay quiet
    } finally {
      _predicting = false;
    }
  }

  // ------------------------------------------------------------------ submitting
  Future<void> _submit() async {
    if (_submitting || _handedIn || _leaving) return;
    setState(() => _submitting = true);
    try {
      final drawing = await _canvas.toBase64();
      final result = await _repo.submitDrawing(
        gameId: widget.gameId,
        drawingBase64: drawing,
      );
      if (!mounted) return;
      if (result.submitted) _myResult = result;
      setState(() {
        _handedIn = true;
        _submitting = false;
        _prediction = null;
      });
      if (result.late) {
        _showMessage('Time was up, so your drawing counted as 0.');
      }
      _applyRoom(result.room); // goes to the result screen if the match is over
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showMessage(e.message);
    }
  }

  void _goToResult() {
    if (_leaving || !mounted) return;
    _leaving = true;
    _stopBackgroundWork();
    context.go('/result?gameId=${widget.gameId}', extra: _myResult);
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave the game?'),
        content: Text(
          _handedIn
              ? 'Your drawing is already in. The result will be saved either way.'
              : 'If you leave now you forfeit this match.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      _leaving = true;
      _stopBackgroundWork();
      context.go('/home');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(body: SafeArea(child: _buildBody())),
    );
  }

  Widget _buildBody() {
    final room = _room;
    if (room == null) {
      if (_loadError != null) return _buildError(_loadError!);
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    if (room.isWaiting) {
      return const Center(
        child: Text(
          'Waiting for the game to start...',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }
    return _buildGame(room);
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
              message,
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
      ),
    );
  }

  Widget _buildGame(GameRoom room) {
    final canDraw =
        room.isActive && !_handedIn && !_submitting && !_clock.isExpired;
    final prediction = _prediction;
    final showBar = prediction != null && _canvas.hasInk && !_handedIn;

    final String submitLabel;
    if (_handedIn) {
      submitLabel = 'Waiting for opponent...';
    } else if (_submitting) {
      submitLabel = 'Submitting...';
    } else {
      submitLabel = 'Submit Drawing';
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: PromptCard(
            prompt: room.prompt,
            secondsLeft: _clock.wholeSecondsLeft,
            totalSeconds: room.timeLimitSeconds,
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: DrawingCanvas(controller: _canvas, enabled: canDraw),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              AiScoreBar(
                promptConfidence: prediction?.promptConfidence ?? 0.0,
                recognizedAs: prediction?.recognizedAs ?? '',
                matchesPrompt: prediction?.matchesPrompt ?? false,
                isVisible: showBar,
              ),
              if (prediction != null && showBar && prediction.model == 'mock')
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Demo AI: the real model is not trained yet',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: canDraw
                          ? () {
                              _canvas.clear();
                              setState(() => _prediction = null);
                            }
                          : null,
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
                      onPressed: (_handedIn || _submitting || !room.isActive)
                          ? null
                          : _submit,
                      child: Text(submitLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}