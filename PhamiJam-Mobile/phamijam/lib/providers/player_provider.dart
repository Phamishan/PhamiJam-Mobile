import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:phamijam/models/edited_song_trim.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/services/drive_duration_cache_service.dart';
import 'package:phamijam/services/google_drive_service.dart'
    show driveTrackIdPrefix;
import 'package:phamijam/services/listening_history_service.dart';
import 'package:phamijam/services/phamijam_audio_handler.dart';
import 'package:phamijam/services/playback_session_sync_service.dart';
import 'package:phamijam/services/playback_state_service.dart';
import 'package:phamijam/services/autoplay_service.dart';
import 'package:phamijam/services/skip_tracking_service.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

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
    _positionSub = _audioHandler.player.positionStream.listen((pos) {
      notifyListeners();
      _checkNearEndFallback(pos);
    });
    _durationSub = _audioHandler.player.durationStream.listen((liveDuration) {
      notifyListeners();
      _maybeCacheDriveDuration(liveDuration);
    });
    _errorSub = _audioHandler.player.playbackEventStream.listen(
      (_) {},
      onError: (Object error, StackTrace stackTrace) =>
          _handleStreamError(error),
    );
    _remoteSessionSub = PlaybackSessionSyncService.watchOtherSession().listen((
      session,
    ) {
      _remoteSession = session;
      if (_isRemoteControlling && session == null) {
        _isRemoteControlling = false;
      }
      notifyListeners();
    });
    _incomingCommandsSub = PlaybackSessionSyncService.watchIncomingCommands()
        .listen(_handleIncomingCommands);
    _sessionHeartbeat = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!_isRemoteControlling && isPlaying) _pushSessionIfHosting();
    });
    _restoreVolume();
    _restoreSession();
  }

  final PhamiJamAudioHandler _audioHandler;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlaybackEvent>? _errorSub;
  StreamSubscription<RemoteSession?>? _remoteSessionSub;
  StreamSubscription<List<RemoteCommand>>? _incomingCommandsSub;
  Timer? _sessionHeartbeat;
  Timer? _volumeCommandThrottle;
  double? _pendingVolumeCommandValue;
  Timer? _sleepTimer;
  DateTime? _sleepTimerEndsAt;
  bool _pauseAtTrackEndScheduled = false;

  Track? _currentTrack;
  List<Track> _queue = [];
  List<Track> _originalQueue = [];
  int _queueIndex = -1;
  Playlist? _currentSourcePlaylist;
  Track? suggestedRemovalTrack;
  Playlist? suggestedRemovalPlaylist;
  bool _shuffle = false;
  PlayerRepeatMode _repeatMode = PlayerRepeatMode.off;
  double _volume = 0.8;
  VideoSurfaceHost _videoSurfaceHost = VideoSurfaceHost.none;
  bool _loaded = false;
  bool _isLoadingTrack = false;
  Duration _pendingResumePosition = Duration.zero;
  bool _endHandled = false;
  DateTime? _lastAutoAdvanceAt;
  DateTime? _lastStreamErrorAt;
  Track? _activePlayTrack;
  DateTime? _activePlayStartedAt;

  RemoteSession? _remoteSession;
  bool _isRemoteControlling = false;
  String? _dismissedRemoteKey;

  EditedSongTrim? Function(String videoId, [String? playlistId])? _trimLookup;
  Duration? _trimStart;
  Duration? _trimEnd;

  void bindEditedSongsLookup(
    EditedSongTrim? Function(String videoId, [String? playlistId]) lookup,
  ) {
    _trimLookup = lookup;
  }

  bool Function()? _autoplayEnabledLookup;
  YTMusic? _ytmusic;
  String? _autoplayAttemptedSeedVideoId;

  void bindAutoplayEnabled(bool Function() lookup) {
    _autoplayEnabledLookup = lookup;
  }

  Future<YTMusic?> _ensureYtMusic() async {
    final existing = _ytmusic;
    if (existing != null) return existing;
    try {
      final created = await YTMusic.create();
      _ytmusic = created;
      return created;
    } catch (error) {
      debugPrint('PlayerProvider: failed to init YTMusic: $error');
      return null;
    }
  }

  Future<bool> _tryAppendAutoplayContinuation() async {
    if (_autoplayEnabledLookup?.call() != true) return false;
    final seedVideoId = _currentTrack?.videoId;
    if (seedVideoId == null || seedVideoId.isEmpty) return false;
    if (_autoplayAttemptedSeedVideoId == seedVideoId) return false;
    _autoplayAttemptedSeedVideoId = seedVideoId;

    final ytmusic = await _ensureYtMusic();
    if (ytmusic == null) return false;
    final excludeIds = _queue.map((t) => t.videoId).whereType<String>().toSet();
    final continuation = await AutoplayService.fetchAutoplayContinuation(
      ytmusic,
      seedVideoId,
      excludeVideoIds: excludeIds,
    );
    if (continuation.isEmpty) return false;
    _queue = List<Track>.from(_queue)..addAll(continuation);
    _originalQueue = List<Track>.from(_originalQueue)..addAll(continuation);
    return true;
  }

  Duration? get trimStart => _trimStart;
  Duration? get trimEnd => _trimEnd;

  Duration _clampToTrim(Duration value) {
    var result = value;
    final start = _trimStart;
    final end = _trimEnd;
    if (start != null && result < start) result = start;
    if (end != null && result > end) result = end;
    return result;
  }

  Future<void> _restoreVolume() async {
    final saved = await PlaybackStateService.loadVolume();
    if (saved == null) return;
    _volume = saved.clamp(0.0, 1.0);
    await _audioHandler.player.setVolume(_volume);
    notifyListeners();
  }

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

  static const int _maxConsecutiveStreamErrors = 3;
  int _consecutiveStreamErrors = 0;

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
      _consecutiveStreamErrors = 0;
    } catch (_) {
      _consecutiveStreamErrors++;
      if (_consecutiveStreamErrors >= _maxConsecutiveStreamErrors) {
        _consecutiveStreamErrors = 0;
        playbackErrorMessage =
            "Having trouble playing music - check your connection.";
        notifyListeners();
        return;
      }
      if (_autoAdvanceRateLimited()) return;
      _localNext();
    }
  }

  void _handlePlayerStateChange(PlayerState state) {
    notifyListeners();

    if (state.processingState == ProcessingState.completed) {
      _handleTrackEnded();
    } else if (state.processingState == ProcessingState.ready) {
      _endHandled = false;
      _consecutiveStreamErrors = 0;
    }
  }

  void _checkNearEndFallback(Duration pos) {
    if (_isRemoteControlling || _endHandled || _isLoadingTrack) return;
    final track = _currentTrack;
    if (track == null) return;
    final trackDuration = _trimEnd ?? duration;
    if (trackDuration <= Duration.zero) return;
    if (!_loaded || !_audioHandler.player.playing) return;
    if (pos < trackDuration - const Duration(milliseconds: 700)) return;
    _handleTrackEnded();
  }

  void _handleTrackEnded() {
    if (_endHandled) return;
    _endHandled = true;
    final track = _currentTrack;
    final playlist = _currentSourcePlaylist;
    final videoId = track?.videoId;
    if (playlist != null && videoId != null && videoId.isNotEmpty) {
      SkipTrackingService.recordCompleted(playlist.id, videoId);
    }
    if (_pauseAtTrackEndScheduled) {
      _pauseAtTrackEndScheduled = false;
      _audioHandler.player.pause();
      notifyListeners();
      return;
    }
    if (_autoAdvanceRateLimited()) return;
    if (_repeatMode == PlayerRepeatMode.one) {
      _replayCurrentTrack();
    } else {
      _localNext();
    }
  }

  Future<void> _recordPotentialSkip() async {
    final track = _currentTrack;
    final playlist = _currentSourcePlaylist;
    final videoId = track?.videoId;
    if (track == null ||
        playlist == null ||
        videoId == null ||
        videoId.isEmpty) {
      return;
    }
    final trackDuration = duration;
    if (trackDuration <= Duration.zero) return;
    final playedFraction =
        position.inMilliseconds / trackDuration.inMilliseconds;
    if (playedFraction >= SkipTrackingService.consideredSkippedBeforeFraction) {
      return;
    }
    final count = await SkipTrackingService.recordSkip(playlist.id, videoId);
    if (count >= SkipTrackingService.skipThreshold) {
      suggestedRemovalTrack = track;
      suggestedRemovalPlaylist = playlist;
      notifyListeners();
    }
  }

  DateTime? get sleepTimerEndsAt => _sleepTimerEndsAt;
  bool get isSleepTimerEndOfTrackScheduled => _pauseAtTrackEndScheduled;
  bool get hasSleepTimer =>
      _sleepTimerEndsAt != null || _pauseAtTrackEndScheduled;

  void setSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _pauseAtTrackEndScheduled = false;
    _sleepTimerEndsAt = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () {
      _sleepTimer = null;
      _sleepTimerEndsAt = null;
      _audioHandler.player.pause();
      notifyListeners();
    });
    notifyListeners();
  }

  void setSleepTimerEndOfTrack() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEndsAt = null;
    _pauseAtTrackEndScheduled = true;
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEndsAt = null;
    _pauseAtTrackEndScheduled = false;
    notifyListeners();
  }

  Future<void> dismissSkipSuggestion() async {
    final track = suggestedRemovalTrack;
    final playlist = suggestedRemovalPlaylist;
    suggestedRemovalTrack = null;
    suggestedRemovalPlaylist = null;
    notifyListeners();
    final videoId = track?.videoId;
    if (playlist != null && videoId != null && videoId.isNotEmpty) {
      await SkipTrackingService.clearForTrack(playlist.id, videoId);
    }
  }

  RemoteSession? get remoteSession => _remoteSession;
  bool get isRemoteControlling => _isRemoteControlling;
  bool get shouldShowRemoteBanner {
    if (_isRemoteControlling) return false;
    final session = _remoteSession;
    if (session == null || !session.isLive) return false;
    final key = session.currentTrack?.videoId;
    return key != null && key != _dismissedRemoteKey;
  }

  void dismissRemoteBanner() {
    _dismissedRemoteKey = _remoteSession?.currentTrack?.videoId;
    notifyListeners();
  }

  Future<void> enterRemoteControl() async {
    if (_remoteSession == null) return;
    if (_currentTrack != null) {
      await _audioHandler.player.pause();
    }
    _isRemoteControlling = true;
    notifyListeners();
  }

  void _exitRemoteControl() {
    if (!_isRemoteControlling) return;
    _isRemoteControlling = false;
    notifyListeners();
  }

  Future<void> resumeRemoteSessionLocally() async {
    final session = _remoteSession;
    final track = session?.currentTrack;
    if (session == null || track == null) return;
    _isRemoteControlling = false;
    _originalQueue = List<Track>.from(session.queue);
    _queue = List<Track>.from(session.queue);
    _queueIndex = session.queueIndex;
    _shuffle = session.shuffle;
    _repeatMode = PlayerRepeatMode.values.firstWhere(
      (m) => m.name == session.repeatMode,
      orElse: () => PlayerRepeatMode.off,
    );
    _currentTrack = track;
    notifyListeners();
    await _tryStartTrack(track, startAt: session.position);
    notifyListeners();
    _persistSession();
  }

  void _pushSessionIfHosting() {
    if (_isRemoteControlling) return;
    final track = _currentTrack;
    if (track == null || track.videoId == null) return;
    PlaybackSessionSyncService.pushSession(
      queue: _queue,
      queueIndex: _queueIndex,
      position: position,
      isPlaying: isPlaying,
      volume: _volume,
      shuffle: _shuffle,
      repeatMode: _repeatMode.name,
    );
  }

  Future<void> _handleIncomingCommands(List<RemoteCommand> commands) async {
    for (final command in commands) {
      switch (command.type) {
        case RemoteCommandType.play:
          if (!_audioHandler.player.playing) await _localTogglePlayPause();
          break;
        case RemoteCommandType.pause:
          if (_audioHandler.player.playing) await _localTogglePlayPause();
          break;
        case RemoteCommandType.next:
          await _localNext();
          break;
        case RemoteCommandType.previous:
          await _localPrevious();
          break;
        case RemoteCommandType.setVolume:
          final value = command.value;
          if (value != null) _localSetVolume(value);
          break;
      }
      await PlaybackSessionSyncService.ackCommand(command.id);
    }
  }

  Track? get currentTrack =>
      _isRemoteControlling ? _remoteSession?.currentTrack : _currentTrack;
  bool get isPlaying => _isRemoteControlling
      ? (_remoteSession?.isPlaying ?? false)
      : _audioHandler.player.playing;
  bool get shuffle =>
      _isRemoteControlling ? (_remoteSession?.shuffle ?? false) : _shuffle;
  PlayerRepeatMode get repeatMode {
    if (!_isRemoteControlling) return _repeatMode;
    return PlayerRepeatMode.values.firstWhere(
      (m) => m.name == _remoteSession?.repeatMode,
      orElse: () => PlayerRepeatMode.off,
    );
  }

  double get volume =>
      _isRemoteControlling ? (_remoteSession?.volume ?? _volume) : _volume;
  Duration get position => _isRemoteControlling
      ? (_remoteSession?.position ?? Duration.zero)
      : (_loaded ? _audioHandler.player.position : _pendingResumePosition);
  Duration get duration {
    if (_isRemoteControlling) {
      return _remoteSession?.currentTrack?.duration ??
          _currentTrack?.duration ??
          Duration.zero;
    }
    final known = _currentTrack?.duration ?? Duration.zero;
    if (known > Duration.zero && !(_currentTrack?.isDriveSourced ?? false)) {
      return known;
    }
    final live = _loaded ? _audioHandler.player.duration : null;
    if (live != null && live > Duration.zero) return live;
    return known;
  }

  void _maybeCacheDriveDuration(Duration? liveDuration) {
    if (liveDuration == null || liveDuration <= Duration.zero) return;
    final track = _currentTrack;
    final videoId = track?.videoId;
    if (track == null || videoId == null || !track.isDriveSourced) return;
    final fileId = videoId.substring(driveTrackIdPrefix.length);
    if (fileId.isEmpty) return;
    unawaited(DriveDurationCacheService.setDuration(fileId, liveDuration));
  }

  List<Track> get queue => List.unmodifiable(
    _isRemoteControlling ? (_remoteSession?.queue ?? const []) : _queue,
  );
  int get queueIndex =>
      _isRemoteControlling ? (_remoteSession?.queueIndex ?? -1) : _queueIndex;
  bool get hasTrack => _isRemoteControlling
      ? _remoteSession?.currentTrack != null
      : _currentTrack != null;
  bool get isLoadingTrack => _isRemoteControlling ? false : _isLoadingTrack;
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

  Future<void> _startTrack(
    Track track, {
    Duration startAt = Duration.zero,
  }) async {
    _finalizeActivePlay();
    _beginActivePlay(track);
    _loaded = true;
    _isLoadingTrack = true;

    final videoId = track.videoId;
    final trim = (videoId != null && videoId.isNotEmpty)
        ? _trimLookup?.call(videoId, _currentSourcePlaylist?.id)
        : null;
    _trimStart = trim != null ? Duration(milliseconds: trim.startMs) : null;
    _trimEnd = trim != null ? Duration(milliseconds: trim.endMs) : null;
    final effectiveStartAt = _clampToTrim(
      startAt == Duration.zero && _trimStart != null ? _trimStart! : startAt,
    );

    notifyListeners();
    try {
      await _audioHandler.loadTrack(track, startAt: effectiveStartAt);
      await _audioHandler.player.setVolume(_volume);
      _prefetchUpcomingTracks();
      _pushSessionIfHosting();
    } finally {
      _isLoadingTrack = false;
      notifyListeners();
    }
  }

  static const int _prefetchWindow = 5;
  void _prefetchUpcomingTracks() {
    if (_queue.isEmpty) return;
    final seen = <int>{_queueIndex};
    var index = _queueIndex;
    for (var i = 0; i < _prefetchWindow; i++) {
      if (index < _queue.length - 1) {
        index++;
      } else if (_repeatMode == PlayerRepeatMode.all) {
        index = 0;
      } else {
        break;
      }
      if (!seen.add(index)) break;
      final videoId = _queue[index].videoId;
      if (videoId == null || videoId.isEmpty) continue;
      _audioHandler.prefetch(videoId);
    }
  }

  Future<bool> _tryStartTrack(
    Track track, {
    Duration startAt = Duration.zero,
  }) async {
    try {
      await _startTrack(track, startAt: startAt);
      return true;
    } catch (error) {
      debugPrint('PlayerProvider: failed to start "${track.title}": $error');
      return false;
    }
  }

  Future<void> playQueue(
    List<Track> tracks, {
    int startIndex = 0,
    Playlist? sourcePlaylist,
  }) async {
    if (tracks.isEmpty) return;
    if (!_isRemoteControlling) unawaited(_recordPotentialSkip());
    _exitRemoteControl();
    _currentSourcePlaylist = sourcePlaylist;
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
    await _startCurrentIndexWithFallback();
    notifyListeners();
    _persistSession();
  }

  Future<void> _startCurrentIndexWithFallback({int attempt = 0}) async {
    final track = _currentTrack;
    if (track == null) return;
    final started = await _tryStartTrack(track);
    if (started) return;
    if (attempt + 1 >= _queue.length || _queueIndex >= _queue.length - 1) {
      playbackErrorMessage = 'Couldn\'t play "${track.title}".';
      notifyListeners();
      return;
    }
    _queueIndex++;
    _currentTrack = _queue[_queueIndex];
    notifyListeners();
    await _startCurrentIndexWithFallback(attempt: attempt + 1);
  }

  String? playbackErrorMessage;

  void consumePlaybackError() {
    playbackErrorMessage = null;
  }

  void shufflePlay(List<Track> tracks, {Playlist? sourcePlaylist}) {
    if (tracks.isEmpty) return;
    _shuffle = true;
    final randomIndex = Random().nextInt(tracks.length);
    playQueue(tracks, startIndex: randomIndex, sourcePlaylist: sourcePlaylist);
  }

  Future<void> togglePlayPause() async {
    if (_isRemoteControlling) {
      await PlaybackSessionSyncService.sendCommand(
        isPlaying ? RemoteCommandType.pause : RemoteCommandType.play,
      );
      return;
    }
    await _localTogglePlayPause();
  }

  Future<void> _localTogglePlayPause() async {
    if (!_loaded) {
      await _resumeRestoredTrack();
      return;
    }
    if (_audioHandler.player.playing) {
      await _audioHandler.player.pause();
    } else {
      unawaited(_audioHandler.player.play());
    }
    _pushSessionIfHosting();
  }

  Future<void> _resumeRestoredTrack() async {
    final track = _currentTrack;
    if (track == null) return;
    final resumeAt = _pendingResumePosition;
    await _tryStartTrack(track, startAt: resumeAt);
    notifyListeners();
  }

  Future<void> next({int skipAttempts = 0}) async {
    if (_isRemoteControlling) {
      if (skipAttempts > 0) return;
      await PlaybackSessionSyncService.sendCommand(RemoteCommandType.next);
      return;
    }
    if (skipAttempts == 0) unawaited(_recordPotentialSkip());
    await _localNext(skipAttempts: skipAttempts);
  }

  Future<void> _localNext({int skipAttempts = 0}) async {
    if (_queue.isEmpty) return;
    if (_queueIndex < _queue.length - 1) {
      _queueIndex++;
    } else if (_repeatMode == PlayerRepeatMode.all) {
      _queueIndex = 0;
    } else {
      final appended = await _tryAppendAutoplayContinuation();
      if (!appended || _queueIndex >= _queue.length - 1) return;
      _queueIndex++;
    }
    _currentTrack = _queue[_queueIndex];
    notifyListeners();
    final started = await _tryStartTrack(_currentTrack!);
    notifyListeners();
    _persistSession();
    if (!started) {
      if (skipAttempts < _queue.length) {
        await _localNext(skipAttempts: skipAttempts + 1);
      } else {
        playbackErrorMessage = "Having trouble playing music - check your connection.";
        notifyListeners();
      }
    }
  }

  Future<void> playFromQueue(int index) async {
    if (index < 0 || index >= _queue.length) return;
    if (!_isRemoteControlling) unawaited(_recordPotentialSkip());
    _exitRemoteControl();
    _queueIndex = index;
    _currentTrack = _queue[index];
    notifyListeners();
    await _startCurrentIndexWithFallback();
    notifyListeners();
    _persistSession();
  }

  void playNext(Track track) {
    _exitRemoteControl();
    if (_currentTrack == null || _queue.isEmpty) {
      playQueue([track]);
      return;
    }
    final insertAt = (_queueIndex + 1).clamp(0, _queue.length);
    _queue = List<Track>.from(_queue)..insert(insertAt, track);
    notifyListeners();
    _prefetchUpcomingTracks();
  }

  void addToQueue(Track track) {
    _exitRemoteControl();
    if (_currentTrack == null || _queue.isEmpty) {
      playQueue([track]);
      return;
    }
    _queue = List<Track>.from(_queue)..add(track);
    notifyListeners();
    _prefetchUpcomingTracks();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    _queue = List<Track>.from(_queue)..removeAt(index);
    if (index < _queueIndex) {
      _queueIndex--;
    }
    notifyListeners();
    _prefetchUpcomingTracks();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex >= _queue.length) return;
    if (oldIndex == newIndex) return;
    final updated = List<Track>.from(_queue);
    final track = updated.removeAt(oldIndex);
    updated.insert(newIndex, track);
    _queue = updated;
    if (oldIndex == _queueIndex) {
      _queueIndex = newIndex;
    } else if (oldIndex < _queueIndex && newIndex >= _queueIndex) {
      _queueIndex--;
    } else if (oldIndex > _queueIndex && newIndex <= _queueIndex) {
      _queueIndex++;
    }
    notifyListeners();
    _prefetchUpcomingTracks();
  }

  void clearQueue() {
    final current = _currentTrack;
    if (current == null) return;
    _queue = [current];
    _originalQueue = [current];
    _queueIndex = 0;
    notifyListeners();
    _persistSession();
  }

  static const Duration _previousRestartThreshold = Duration(seconds: 3);

  bool get _pastPreviousRestartThreshold =>
      position > _previousRestartThreshold;

  Future<void> previous() async {
    if (_isRemoteControlling) {
      await PlaybackSessionSyncService.sendCommand(RemoteCommandType.previous);
      return;
    }
    if (!_pastPreviousRestartThreshold) {
      unawaited(_recordPotentialSkip());
    }
    await _localPrevious();
  }

  Future<void> _localPrevious() async {
    if (_queue.isEmpty) return;
    if (_pastPreviousRestartThreshold || _queueIndex <= 0) {
      seek(Duration.zero);
      return;
    }
    _queueIndex--;
    _currentTrack = _queue[_queueIndex];
    notifyListeners();
    await _tryStartTrack(_currentTrack!);
    notifyListeners();
    _persistSession();
  }

  Future<void> _replayCurrentTrack() async {
    final track = _currentTrack;
    if (track == null) return;
    final started = await _tryStartTrack(track);
    if (!started) await _localNext();
  }

  Future<void> dismissPlayback() async {
    _exitRemoteControl();
    _finalizeActivePlay();
    await _audioHandler.player.stop();
    _currentTrack = null;
    _queue = [];
    _originalQueue = [];
    _queueIndex = -1;
    _currentSourcePlaylist = null;
    suggestedRemovalTrack = null;
    suggestedRemovalPlaylist = null;
    _loaded = false;
    _pendingResumePosition = Duration.zero;
    _endHandled = false;
    _videoSurfaceHost = VideoSurfaceHost.none;
    notifyListeners();
    await PlaybackStateService.clear();
  }

  void toggleShuffle() {
    if (_isRemoteControlling) return;
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
    _prefetchUpcomingTracks();
    _pushSessionIfHosting();
  }

  void cycleRepeatMode() {
    if (_isRemoteControlling) return;
    _repeatMode = PlayerRepeatMode
        .values[(_repeatMode.index + 1) % PlayerRepeatMode.values.length];
    notifyListeners();
    _pushSessionIfHosting();
  }

  void setVolume(double value) {
    if (_isRemoteControlling) {
      _sendVolumeCommandThrottled(value.clamp(0.0, 1.0));
      return;
    }
    _localSetVolume(value);
  }

  void _sendVolumeCommandThrottled(double value) {
    _pendingVolumeCommandValue = value;
    if (_volumeCommandThrottle != null) return;
    PlaybackSessionSyncService.sendCommand(
      RemoteCommandType.setVolume,
      value: value,
    );
    _volumeCommandThrottle = Timer(const Duration(milliseconds: 150), () {
      _volumeCommandThrottle = null;
      final pending = _pendingVolumeCommandValue;
      if (pending != null) {
        _pendingVolumeCommandValue = null;
        _sendVolumeCommandThrottled(pending);
      }
    });
  }

  void _localSetVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _audioHandler.player.setVolume(_volume);
    notifyListeners();
    PlaybackStateService.saveVolume(_volume);
    _pushSessionIfHosting();
  }

  void seek(Duration position) {
    if (_isRemoteControlling) return;
    final clamped = _clampToTrim(position);
    _audioHandler.player.seek(clamped);
    if (!_loaded) _pendingResumePosition = clamped;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _finalizeActivePlay();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _errorSub?.cancel();
    _remoteSessionSub?.cancel();
    _incomingCommandsSub?.cancel();
    _sessionHeartbeat?.cancel();
    _volumeCommandThrottle?.cancel();
    _sleepTimer?.cancel();
    super.dispose();
  }
}
