import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/services/listening_history_service.dart';
import 'package:phamijam/services/playback_state_service.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

enum PlayerRepeatMode { off, all, one }

enum VideoSurfaceHost { none, nowPlaying, fullscreen }

class PlayerProvider extends ChangeNotifier with WidgetsBindingObserver {
  PlayerProvider() {
    WidgetsBinding.instance.addObserver(this);
    _restoreSession();
  }

  Track? _currentTrack;
  List<Track> _queue = [];
  List<Track> _originalQueue = [];
  int _queueIndex = -1;
  bool _shuffle = false;
  PlayerRepeatMode _repeatMode = PlayerRepeatMode.off;
  double _volume = 0.8;

  YoutubePlayerController? _controller;
  VideoSurfaceHost _videoSurfaceHost = VideoSurfaceHost.none;

  bool _resyncing = false;

  Duration _basePosition = Duration.zero;
  DateTime? _basePositionAnchor;

  bool _endHandled = false;

  int _handledErrorCode = 0;

  DateTime? _lastAutoAdvanceAt;

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
    _basePosition = saved.position;
    _basePositionAnchor = null;
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

  Track? get currentTrack => _currentTrack;
  bool get isPlaying => _controller?.value.isPlaying ?? false;
  bool get shuffle => _shuffle;
  PlayerRepeatMode get repeatMode => _repeatMode;
  double get volume => _volume;
  Duration get position {
    final anchor = _basePositionAnchor;
    if (anchor == null) return _basePosition;
    return _basePosition + DateTime.now().difference(anchor);
  }

  List<Track> get queue => List.unmodifiable(_queue);
  int get queueIndex => _queueIndex;
  bool get hasTrack => _currentTrack != null;

  YoutubePlayerController? get youtubeController => _controller;
  VideoSurfaceHost get videoSurfaceHost => _videoSurfaceHost;

  void setVideoSurfaceHost(VideoSurfaceHost host) {
    if (_videoSurfaceHost == host) return;
    _videoSurfaceHost = host;
    notifyListeners();
  }

  void resyncVideoSurface() {
    final controller = _controller;
    final videoId = _currentTrack?.videoId;
    if (controller == null || videoId == null || videoId.isEmpty) return;

    final resumeAt = position;
    _resyncing = true;
    _basePosition = resumeAt;
    _basePositionAnchor = DateTime.now();

    controller.mute();
    controller.load(videoId, startAt: resumeAt.inSeconds);

    final expectedVideoId = videoId;
    Future.delayed(const Duration(milliseconds: 350), () {
      if (_controller == controller &&
          _currentTrack?.videoId == expectedVideoId) {
        controller.seekTo(position);
      }
    });

    Future.delayed(const Duration(milliseconds: 800), () {
      _resyncing = false;
      if (_controller == controller &&
          _currentTrack?.videoId == expectedVideoId) {
        if (_volume > 0) controller.unMute();
        controller.setVolume((_volume * 100).round());
      }
    });
  }

  void _resetPositionTracking() {
    _basePosition = Duration.zero;
    _basePositionAnchor = DateTime.now();
  }

  void _loadIntoController(String? videoId) {
    if (videoId == null || videoId.isEmpty) return;
    _finalizeActivePlay();
    _beginActivePlay(_currentTrack);
    _resetPositionTracking();
    _resyncing = false;
    _controller?.unMute();
    _controller?.setVolume((_volume * 100).round());
    if (_controller == null) {
      _controller = YoutubePlayerController(
        initialVideoId: videoId,
        flags: const YoutubePlayerFlags(
          autoPlay: true,
          mute: false,
          hideControls: true,
          hideThumbnail: true,
        ),
      )..addListener(_handleControllerUpdate);
    } else {
      final controller = _controller!;
      controller.load(videoId);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_controller == controller && _currentTrack?.videoId == videoId) {
          controller.play();
        }
      });
    }
  }

  void _updatePositionTracking(YoutubePlayerValue value) {
    if (_resyncing) return;
    if (_videoSurfaceHost != VideoSurfaceHost.none) {
      _basePosition = value.position;
      _basePositionAnchor = value.isPlaying ? DateTime.now() : null;
      return;
    }
    if (value.isPlaying) {
      _basePositionAnchor ??= DateTime.now();
    } else if (_basePositionAnchor != null) {
      _basePosition = position;
      _basePositionAnchor = null;
    }
  }

  void _handleControllerUpdate() {
    notifyListeners();
    final value = _controller?.value;
    if (value == null) return;
    _updatePositionTracking(value);

    if (value.hasError) {
      if (value.errorCode == _handledErrorCode) return;
      _handledErrorCode = value.errorCode;
      if (_autoAdvanceRateLimited()) return;
      debugPrint(
        'PlayerProvider: playback error ${value.errorCode} for '
        '"${_currentTrack?.title}" — skipping to next track.',
      );
      next();
      return;
    }
    _handledErrorCode = 0;

    if (value.playerState == PlayerState.ended) {
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

  void _replayCurrentTrack() {
    final videoId = _currentTrack?.videoId;
    if (videoId == null || videoId.isEmpty) return;
    _finalizeActivePlay();
    _beginActivePlay(_currentTrack);
    _resetPositionTracking();
    _controller?.load(videoId);
  }

  void playQueue(List<Track> tracks, {int startIndex = 0}) {
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
    _loadIntoController(_currentTrack?.videoId);
    notifyListeners();
    _persistSession();
  }

  void shufflePlay(List<Track> tracks) {
    if (tracks.isEmpty) return;
    _shuffle = true;
    final randomIndex = Random().nextInt(tracks.length);
    playQueue(tracks, startIndex: randomIndex);
  }

  void togglePlayPause() {
    final controller = _controller;
    if (controller == null) {
      _resumeRestoredTrack();
      return;
    }
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  void _resumeRestoredTrack() {
    final videoId = _currentTrack?.videoId;
    if (videoId == null || videoId.isEmpty) return;
    final resumeAt = _basePosition;
    _loadIntoController(videoId);
    notifyListeners();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_currentTrack?.videoId == videoId) {
        _controller?.seekTo(resumeAt);
        _basePosition = resumeAt;
        _basePositionAnchor = DateTime.now();
      }
    });
  }

  void next() {
    if (_queue.isEmpty) return;
    if (_queueIndex < _queue.length - 1) {
      _queueIndex++;
    } else if (_repeatMode == PlayerRepeatMode.all) {
      _queueIndex = 0;
    } else {
      return;
    }
    _currentTrack = _queue[_queueIndex];
    _loadIntoController(_currentTrack?.videoId);
    notifyListeners();
    _persistSession();
  }

  void playFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queueIndex = index;
    _currentTrack = _queue[index];
    _loadIntoController(_currentTrack?.videoId);
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

  void previous() {
    if (_queue.isEmpty) return;
    if (_queueIndex > 0) {
      _queueIndex--;
      _currentTrack = _queue[_queueIndex];
      _loadIntoController(_currentTrack?.videoId);
      notifyListeners();
      _persistSession();
    }
  }

  void dismissPlayback() {
    _finalizeActivePlay();
    _controller?.removeListener(_handleControllerUpdate);
    _controller?.dispose();
    _controller = null;
    _currentTrack = null;
    _queue = [];
    _originalQueue = [];
    _queueIndex = -1;
    _basePosition = Duration.zero;
    _basePositionAnchor = null;
    _endHandled = false;
    _handledErrorCode = 0;
    _videoSurfaceHost = VideoSurfaceHost.none;
    notifyListeners();
    PlaybackStateService.clear();
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
    _controller?.setVolume((_volume * 100).round());
    notifyListeners();
  }

  void seek(Duration position) {
    _controller?.seekTo(position);
    _basePosition = position;
    _basePositionAnchor = DateTime.now();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _finalizeActivePlay();
    _controller?.removeListener(_handleControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }
}
