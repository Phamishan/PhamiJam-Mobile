import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class CrossfadeController {
  AudioPlayer? _fadePlayer;
  Timer? _timer;
  bool _active = false;
  Future<void> Function(double volume0to1)? _restoreMainVolume;
  double _targetVolume = 1;
  static const Duration _rampSafetyMargin = Duration(milliseconds: 150);

  bool get isActive => _active;

  Future<void> begin({
    required Future<void> Function(AudioPlayer fadePlayer) load,
    required Duration crossfadeDuration,
    required double targetVolume,
    required Duration Function() remainingOnMain,
    required Future<void> Function(double volume0to1) setMainVolume,
    required Future<void> Function(Duration startAt) onComplete,
  }) async {
    cancel();
    debugPrint('[crossfade] begin: opening next track on fade player');
    final fadePlayer = AudioPlayer();
    _fadePlayer = fadePlayer;
    _active = true;
    _restoreMainVolume = setMainVolume;
    _targetVolume = targetVolume;

    final loadStopwatch = Stopwatch()..start();
    try {
      await fadePlayer.setVolume(0);
      await load(fadePlayer).timeout(const Duration(seconds: 12));
      unawaited(fadePlayer.play());
    } catch (error, stackTrace) {
      debugPrint(
        '[crossfade] load FAILED after ${loadStopwatch.elapsedMilliseconds}ms: $error\n$stackTrace',
      );
      if (identical(_fadePlayer, fadePlayer)) {
        _active = false;
        _fadePlayer = null;
        _restoreMainVolume = null;
      }
      unawaited(fadePlayer.dispose());
      return;
    }
    if (!_active || !identical(_fadePlayer, fadePlayer)) {
      debugPrint('[crossfade] cancelled during load, aborting');
      return;
    }
    debugPrint(
      '[crossfade] load complete in ${loadStopwatch.elapsedMilliseconds}ms',
    );

    final remaining = remainingOnMain();
    final cappedMs = (remaining - _rampSafetyMargin).inMilliseconds;
    final totalMs =
        (crossfadeDuration.inMilliseconds < cappedMs
                ? crossfadeDuration.inMilliseconds
                : cappedMs)
            .clamp(1, 1 << 30);
    debugPrint(
      '[crossfade] remainingOnMain=$remaining nominalDuration=$crossfadeDuration -> rampMs=$totalMs',
    );

    final stopwatch = Stopwatch()..start();
    final completer = Completer<void>();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!_active || !identical(_fadePlayer, fadePlayer)) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
        return;
      }
      final t = (stopwatch.elapsedMilliseconds / totalMs).clamp(0.0, 1.0);
      unawaited(fadePlayer.setVolume(t * targetVolume));
      unawaited(setMainVolume((1 - t) * targetVolume));
      if (t >= 1.0) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });
    await completer.future;

    if (!_active || !identical(_fadePlayer, fadePlayer)) {
      debugPrint('[crossfade] cancelled during ramp, aborting handoff');
      return;
    }
    final startAt = fadePlayer.position;
    debugPrint(
      '[crossfade] ramp complete in ${stopwatch.elapsedMilliseconds}ms, handing off at $startAt',
    );
    _fadePlayer = null;
    _restoreMainVolume = null;
    await onComplete(startAt);
    await setMainVolume(targetVolume);
    _active = false;
    debugPrint('[crossfade] handoff complete');
    unawaited(fadePlayer.dispose());
  }

  void cancel() {
    if (!_active && _fadePlayer == null) return;
    debugPrint('[crossfade] cancel() called');
    _active = false;
    _timer?.cancel();
    _timer = null;

    final restore = _restoreMainVolume;
    final target = _targetVolume;
    _restoreMainVolume = null;
    if (restore != null) {
      unawaited(restore(target));
    }

    final fadePlayer = _fadePlayer;
    _fadePlayer = null;
    if (fadePlayer != null) {
      unawaited(fadePlayer.dispose());
    }
  }

  void dispose() => cancel();
}
