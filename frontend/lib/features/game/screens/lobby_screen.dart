import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:sketchduel_app/core/theme/app_theme.dart';
import 'package:sketchduel_app/core/utils/supabase_client.dart';
import 'package:sketchduel_app/data/repositories/game_repository.dart';

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
  String? _roomCode;
  String? _gameId;
  String? _prompt;

  String get _token =>
      SupabaseClientHelper.client.auth.currentSession?.accessToken ?? '';
  String get _userId => SupabaseClientHelper.currentUser?.id ?? '';

  Future<void> _createRoom() async {
    setState(() => _loading = true);
    try {
      final result = await _repo.createRoom(_userId, _token);
      setState(() {
        _roomCode = result['room_code'];
        _gameId = result['game_id'];
        _prompt = result['prompt'];
      });
      // Listen for second player to join
      _waitForOpponent(_gameId!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _waitForOpponent(String gameId) {
    SupabaseClientHelper.listenToRoom(gameId, (room) {
      if (room['status'] == 'active' && mounted) {
        context.go('/game?roomCode=${room['room_code']}&gameId=$gameId&prompt=${room['prompt']}&isPlayer1=true');
      }
    });
  }

  Future<void> _joinRoom() async {
    if (_codeCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    try {
      final room = await _repo.joinRoom(
          _codeCtrl.text.trim().toUpperCase(), _userId, _token);
      if (mounted) {
        context.go('/game?roomCode=${room.roomCode}&gameId=${room.id}&prompt=${room.prompt}&isPlayer1=false');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Room not found: $e')));
      }
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
    if (_roomCode != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Room Created!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
            ),
            child: Column(
              children: [
                const Text('Share this code:',
                    style: TextStyle(color: AppTheme.textSecondary)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _roomCode!,
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
                        Clipboard.setData(ClipboardData(text: _roomCode!));
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
                  'You\'ll draw: $_prompt',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ).animate().scale(),
          const SizedBox(height: 32),
          const CircularProgressIndicator(color: AppTheme.primary),
          const SizedBox(height: 16),
          const Text('Waiting for opponent...',
              style: TextStyle(color: AppTheme.textSecondary)),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.add_circle_outline, size: 80, color: AppTheme.primary)
            .animate()
            .scale(),
        const SizedBox(height: 24),
        const Text('Create a new room and share the code with a friend.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary)),
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
                        strokeWidth: 2, color: Colors.white))
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
        const Icon(Icons.login, size: 80, color: AppTheme.secondary)
            .animate()
            .scale(),
        const SizedBox(height: 24),
        const Text('Enter the 6-character room code.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary)),
        const SizedBox(height: 32),
        TextField(
          controller: _codeCtrl,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          textAlign: TextAlign.center,
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
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondary),
            onPressed: _loading ? null : _joinRoom,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Join Room'),
          ),
        ),
      ],
    );
  }
}