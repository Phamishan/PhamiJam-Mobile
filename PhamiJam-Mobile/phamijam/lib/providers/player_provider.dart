import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/services/listening_history_service.dart';
import 'package:phamijam/services/phamijam_audio_handler.dart';
import 'package:phamijam/services/playback_state_service.dart';

enum PlayerRepeatMode { off, all, one }

enum VideoSurfaceHost { none, nowPlaying, fullscreen }

class PlayerProvider extends ChangeNotifier with WidgetsBindingObserver {
  PlayerProvider({required PhamiJamAudioHandler audioHandler})
    : _audioHandler = audioHandler {
    WidgetsBinding.instance.addObserver(this);
    _audioHandler.onPlayRequested = togglePlayPause;
    _audioHandler.onPauseRequested = togglePlayPause;
    _audioHandler.onNextRequested = next;
    _audioHandler.onPreviousRequested = previous;
    _audioHandler.onStopRequested = dismissPlayback;
    _playerStateSub = _audioHandler.player.playerStateStream.listen(
      _handlePlayerStateChange,
    );
    _positionSub = _audioHandler.player.positionStream.listen((_) {
      notifyListeners();
    });
    _errorSub = _audioHandler.player.playbackEventStream.listen(
      (_) {},
      onError: (Object error, StackTrace stackTrace) =>
          _handleStreamError(error),
    );
    _restoreSession();
  }

  final PhamiJamAudioHandler _audioHandler;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlaybackEvent>? _errorSub;

  Track? _currentTrack;
  List<Track> _queue = [];
  List<Track> _originalQueue = [];
  int _queueIndex = -1;
  bool _shuffle = false;
  PlayerRepeatMode _repeatMode = PlayerRepeatMode.off;
  double _volume = 0.8;
  VideoSurfaceHost _videoSurfaceHost = VideoSurfaceHost.none;
  bool _loaded = false;
  Duration _pendingResumePosition = Duration.zero;
  bool _endHandled = false;
  DateTime? _lastAutoAdvanceAt;
  DateTime? _lastStreamErrorAt;
  Track? _activePlayTrack;
  DateTime? _activePlayStartedAt;

  Future<void> _restoreSession() async {
    final saved = await PlaybackStateService.load();
    if (saved == null) return;
    _queue = saved.queue;
    _originalQueue = saved.originalQueue;
    _queueIndex = saved.queueIndex;
    _currentTrack = _queue[_queueIndex];
    _shuffle = saved.shuffle;
    _repeatMode = PlayerRepeatMode.values.firstWhere(
      (m) => m.name == saved.repeatMode,
      orElse: () => PlayerRepeatMode.off,
    );
    _pendingResumePosition = Duration.zero;
    _loaded = false;
    notifyListeners();
  }

  void _persistSession() {
    PlaybackStateService.save(
      queue: _queue,
      originalQueue: _originalQueue,
      queueIndex: _queueIndex,
      position: position,
      shuffle: _shuffle,
      repeatMode: _repeatMode.name,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _persistSession();
    }
  }

  void _finalizeActivePlay() {
    final track = _activePlayTrack;
    final startedAt = _activePlayStartedAt;
    _activePlayTrack = null;
    _activePlayStartedAt = null;
    if (track == null || startedAt == null) return;
    ListeningHistoryService.logPlay(
      track: track,
      startedAt: startedAt,
      listened: position,
    );
  }

  void _beginActivePlay(Track? track) {
    _activePlayTrack = track;
    _activePlayStartedAt = DateTime.now();
  }

  bool _autoAdvanceRateLimited() {
    final last = _lastAutoAdvanceAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(milliseconds: 800)) {
      return true;
    }
    _lastAutoAdvanceAt = DateTime.now();
    return false;
  }

  Future<void> _handleStreamError(Object error) async {
    final track = _currentTrack;
    if (track == null) return;
    final last = _lastStreamErrorAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _lastStreamErrorAt = DateTime.now();
    try {
      await _audioHandler.reloadAfterStreamError(track);
    } catch (_) {
      if (_autoAdvanceRateLimited()) return;
      next();
    }
  }

  void _handlePlayerStateChange(PlayerState state) {
    notifyListeners();

    if (state.processingState == ProcessingState.completed) {
      if (_endHandled) return;
      _endHandled = true;
      if (_autoAdvanceRateLimited()) return;
      if (_repeatMode == PlayerRepeatMode.one) {
        _replayCurrentTrack();
      } else {
        next();
      }
    } else {
      _endHandled = false;
    }
  }

  Track? get currentTrack => _currentTrack;
  bool get isPlaying => _audioHandler.player.playing;
  bool get shuffle => _shuffle;
  PlayerRepeatMode get repeatMode => _repeatMode;
  double get volume => _volume;
  Duration get position =>
      _loaded ? _audioHandler.player.position : _pendingResumePosition;
  List<Track> get queue => List.unmodifiable(_queue);
  int get queueIndex => _queueIndex;
  bool get hasTrack => _currentTrack != null;
  VideoSurfaceHost get videoSurfaceHost => _videoSurfaceHost;

  Future<Uri?> videoOnlyUrlForCurrentTrack() {
    final videoId = _currentTrack?.videoId;
    if (videoId == null || videoId.isEmpty) return Future.value(null);
    return _audioHandler.videoOnlyUrlFor(videoId);
  }

  void setVideoSurfaceHost(VideoSurfaceHost host) {
    if (_videoSurfaceHost == host) return;
    _videoSurfaceHost = host;
    notifyListeners();
  }

  bool _notificationPermissionRequested = false;

  void _requestNotificationPermissionOnce() {
    if (_notificationPermissionRequested) return;
    _notificationPermissionRequested = true;
    Permission.notification.request();
  }

  Future<void> _startTrack(
    Track track, {
    Duration startAt = Duration.zero,
  }) async {
    _requestNotificationPermissionOnce();
    _finalizeActivePlay();
    _beginActivePlay(track);
    _endHandled = false;
    _loaded = true;
    await _audioHandler.loadTrack(track, startAt: startAt);
    await _audioHandler.player.setVolume(_volume);
  }

  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty) return;
    _originalQueue = List<Track>.from(tracks);
    final clampedStart = startIndex.clamp(0, tracks.length - 1);
    final startTrack = tracks[clampedStart];

    if (_shuffle) {
      final rest = tracks.where((t) => t.id != startTrack.id).toList()
        ..shuffle();
      _queue = [startTrack, ...rest];
      _queueIndex = 0;
    } else {
      _queue = List<Track>.from(tracks);
      _queueIndex = clampedStart;
    }

    _currentTrack = _queue[_queueIndex];
    notifyListeners();
    await _startTrack(_currentTrack!);
    notifyListeners();
    _persistSession();
  }

  void shufflePlay(List<Track> tracks) {
    if (tracks.isEmpty) return;
    _shuffle = true;
    final randomIndex = Random().nextInt(tracks.length);
    playQueue(tracks, startIndex: randomIndex);
  }

  Future<void> togglePlayPause() async {
    if (!_loaded) {
      await _resumeRestoredTrack();
      return;
    }
    if (_audioHandler.player.playing) {
      await _audioHandler.player.pause();
    } else {
      await _audioHandler.player.play();
    }
  }

  Future<void> _resumeRestoredTrack() async {
    final track = _currentTrack;
    if (track == null) return;
    final resumeAt = _pendingResumePosition;
    await _startTrack(track, startAt: resumeAt);
    notifyListeners();
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_queueIndex < _queue.length - 1) {
      _queueIndex++;
    } else if (_repeatMode == PlayerRepeatMode.all) {
      _queueIndex = 0;
    } else {
      return;
    }
    _currentTrack = _queue[_queueIndex];
    notifyListeners();
    await _startTrack(_currentTrack!);
    notifyListeners();
    _persistSession();
  }

  Future<void> playFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _queueIndex = index;
    _currentTrack = _queue[index];
    notifyListeners();
    await _startTrack(_currentTrack!);
    notifyListeners();
    _persistSession();
  }

  void playNext(Track track) {
    if (_currentTrack == null || _queue.isEmpty) {
      playQueue([track]);
      return;
    }
    final insertAt = (_queueIndex + 1).clamp(0, _queue.length);
    _queue = List<Track>.from(_queue)..insert(insertAt, track);
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queue = List<Track>.from(_queue)..removeAt(index);
    if (index < _queueIndex) {
      _queueIndex--;
    }
    notifyListeners();
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (_queueIndex > 0) {
      _queueIndex--;
      _currentTrack = _queue[_queueIndex];
      notifyListeners();
      await _startTrack(_currentTrack!);
      notifyListeners();
      _persistSession();
    }
  }

  Future<void> _replayCurrentTrack() async {
    final track = _currentTrack;
    if (track == null) return;
    await _startTrack(track);
  }

  Future<void> dismissPlayback() async {
    _finalizeActivePlay();
    await _audioHandler.player.stop();
    _currentTrack = null;
    _queue = [];
    _originalQueue = [];
    _queueIndex = -1;
    _loaded = false;
    _pendingResumePosition = Duration.zero;
    _endHandled = false;
    _videoSurfaceHost = VideoSurfaceHost.none;
    notifyListeners();
    await PlaybackStateService.clear();
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;

    if (_currentTrack != null && _originalQueue.isNotEmpty) {
      final current = _currentTrack!;
      if (_shuffle) {
        final rest = _originalQueue.where((t) => t.id != current.id).toList()
          ..shuffle();
        _queue = [current, ...rest];
        _queueIndex = 0;
      } else {
        _queue = List<Track>.from(_originalQueue);
        final restoredIndex = _queue.indexWhere((t) => t.id == current.id);
        _queueIndex = restoredIndex < 0 ? 0 : restoredIndex;
      }
    }

    notifyListeners();
  }

  void cycleRepeatMode() {
    _repeatMode = PlayerRepeatMode
        .values[(_repeatMode.index + 1) % PlayerRepeatMode.values.length];
    notifyListeners();
  }

  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _audioHandler.player.setVolume(_volume);
    notifyListeners();
  }

  void seek(Duration position) {
    _audioHandler.player.seek(position);
    if (!_loaded) _pendingResumePosition = position;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _finalizeActivePlay();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }
}
