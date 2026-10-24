import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:sketchduel_app/core/constants/app_constants.dart';
import 'package:sketchduel_app/core/theme/app_theme.dart';
import 'package:sketchduel_app/core/utils/supabase_client.dart';
import 'package:sketchduel_app/data/datasources/api_datasource.dart';
import 'package:sketchduel_app/data/models/game_model.dart';
import 'package:sketchduel_app/data/repositories/game_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LobbyScreen extends StatefulWidget {
  final String mode; // 'create' or 'join'
  const LobbyScreen({super.key, required this.mode});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final _repo = GameRepository();
  final _codeCtrl = TextEditingController();

  bool _loading = false;
  CreatedRoom? _created;

  Timer? _poller;
  RealtimeChannel? _channel;
  bool _checking = false;
  bool _entered = false;

  @override
  void dispose() {
    _stopWaiting();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createRoom() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final created = await _repo.createRoom();
      if (!mounted) return;
      setState(() => _created = created);
      _startWaiting(created.gameId);
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Waits for the second player. Realtime gives an instant nudge, polling is the safety net.
  void _startWaiting(String gameId) {
    try {
      _channel = SupabaseClientHelper.listenToRoom(
        gameId,
        (_) => _checkRoom(gameId),
      );
    } catch (_) {
      _channel = null; // polling alone is enough
    }
    _poller = Timer.periodic(
      const Duration(seconds: AppConstants.roomPollIntervalSeconds),
      (_) => _checkRoom(gameId),
    );
  }

  void _stopWaiting() {
    _poller?.cancel();
    _poller = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(SupabaseClientHelper.stopListening(channel));
  }

  Future<void> _checkRoom(String gameId) async {
    if (_checking || _entered || !mounted) return;
    _checking = true;
    try {
      final room = await _repo.getRoom(gameId);
      if (!mounted || _entered) return;
      if (room.isActive || room.isFinished) _enterGame(gameId);
    } on ApiException catch (_) {
      // a network blip: the next check tries again
    } finally {
      _checking = false;
    }
  }

  void _enterGame(String gameId) {
    if (_entered || !mounted) return;
    _entered = true;
    _stopWaiting();
    context.go('/game?gameId=$gameId');
  }

  Future<void> _joinRoom() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 4) {
      _showError('Enter the room code your friend shared.');
      return;
    }
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final room = await _repo.joinRoom(code);
      if (!mounted) return;
      _enterGame(room.id);
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCreate = widget.mode == 'create';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
        title: Text(isCreate ? 'Create Room' : 'Join Room'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: isCreate ? _buildCreate() : _buildJoin(),
      ),
    );
  }

  Widget _buildCreate() {
    final created = _created;
    if (created != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Room Created!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              children: [
                const Text(
                  'Share this code:',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      created.roomCode,
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                        letterSpacing: 6,
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: created.roomCode),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code copied!')),
                        );
                      },
                      icon: const Icon(Icons.copy, color: AppTheme.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  "You'll draw: ${created.prompt}",
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ).animate().scale(),
          const SizedBox(height: 32),
          const CircularProgressIndicator(color: AppTheme.primary),
          const SizedBox(height: 16),
          const Text(
            'Waiting for opponent...',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.add_circle_outline,
          size: 80,
          color: AppTheme.primary,
        ).animate().scale(),
        const SizedBox(height: 24),
        const Text(
          'Create a new room and share the code with a friend.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _createRoom,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Create Room'),
          ),
        ),
      ],
    );
  }

  Widget _buildJoin() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.login,
          size: 80,
          color: AppTheme.secondary,
        ).animate().scale(),
        const SizedBox(height: 24),
        const Text(
          'Enter the 6-character room code.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _codeCtrl,
          textCapitalization: TextCapitalization.characters,
          maxLength: AppConstants.maxRoomCodeLength,
          textAlign: TextAlign.center,
          onSubmitted: (_) => _joinRoom(),
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: 6,
            color: AppTheme.textPrimary,
          ),
          decoration: const InputDecoration(
            hintText: 'XXXXXX',
            counterText: '',
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.secondary,
            ),
            onPressed: _loading ? null : _joinRoom,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Join Room'),
          ),
        ),
      ],
    );
  }
}