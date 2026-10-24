import 'dart:math' as math;

/// Counts down the drawing time using the SERVER's reading of the clock.
///
/// The server tells us how many seconds are left ([sync]); between answers we count down with a
/// monotonic stopwatch, so changing the phone's clock cannot buy extra time. Each new answer from
/// the server re-synchronises the countdown and cancels any drift.
class GameClock {
  GameClock({required this.limitSeconds, Duration Function()? uptime})
    : _uptime = uptime ?? _stopwatchUptime();

  /// Length of the drawing phase (the most [secondsLeft] can ever be).
  final int limitSeconds;
  final Duration Function() _uptime;

  double? _remainingAtSync;
  Duration _syncedAt = Duration.zero;

  static Duration Function() _stopwatchUptime() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  /// True once the server has told us the remaining time at least once.
  bool get isSynced => _remainingAtSync != null;

  /// Call with `seconds_remaining` from the server. A null value (game not active) is ignored.
  void sync(double? secondsRemaining) {
    if (secondsRemaining == null) return;
    _remainingAtSync = secondsRemaining;
    _syncedAt = _uptime();
  }

  /// Seconds left, never below 0 and never above [limitSeconds].
  double get secondsLeft {
    final base = _remainingAtSync;
    if (base == null) return limitSeconds.toDouble();
    final elapsed = (_uptime() - _syncedAt).inMilliseconds / 1000.0;
    return math.max(0.0, math.min(limitSeconds.toDouble(), base - elapsed));
  }

  /// What the countdown shows: 60, 59, ... 1, 0.
  int get wholeSecondsLeft => secondsLeft.ceil();

  /// True only after a sync and once the time has run out.
  bool get isExpired => isSynced && secondsLeft <= 0;
}