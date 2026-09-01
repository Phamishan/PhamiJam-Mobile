import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/services/audio_stream_resolver.dart';
import 'package:phamijam/services/google_drive_service.dart';

class PhamiJamAudioHandler extends BaseAudioHandler {
  PhamiJamAudioHandler({AudioStreamResolver? resolver})
    : _resolver = resolver ?? AudioStreamResolver() {
    _wirePlayerStreams();
  }

  final AudioStreamResolver _resolver;
  final AudioPlayer player = AudioPlayer();

  static const Map<String, String> _youtubeHttpHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Mobile Safari/537.36',
    'Referer': 'https://www.youtube.com/',
  };

  FutureOr<void> Function()? onPlayRequested;
  FutureOr<void> Function()? onPauseRequested;
  FutureOr<void> Function()? onNextRequested;
  FutureOr<void> Function()? onPreviousRequested;
  FutureOr<void> Function()? onStopRequested;

  String? Function(String videoId)? resolveLocalPath;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<PlaybackEvent>? _eventSub;
  int _loadRequestId = 0;

  void _wirePlayerStreams() {
    _playerStateSub = player.playerStateStream.listen((state) {
      _pushPlaybackState(
        playing: state.playing,
        processingState: _mapProcessingState(state.processingState),
        position: player.position,
      );
    });

    _eventSub = player.playbackEventStream.listen((_) {}, onError: (_, _) {});
  }

  void _pushPlaybackState({
    required bool playing,
    required AudioProcessingState processingState,
    Duration position = Duration.zero,
  }) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processingState,
        playing: playing,
        updatePosition: position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
      ),
    );
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  Future<void> loadTrack(
    Track track, {
    Duration startAt = Duration.zero,
    bool autoPlay = true,
  }) async {
    final videoId = track.videoId;
    if (videoId == null || videoId.isEmpty) return;
    final requestId = ++_loadRequestId;

    mediaItem.add(
      MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artist,
        artUri: Uri.tryParse(track.thumbnailUrl),
        duration: track.duration,
        extras: {'videoId': videoId},
      ),
    );
    _pushPlaybackState(
      playing: autoPlay,
      processingState: AudioProcessingState.loading,
      position: startAt,
    );

    if (videoId.startsWith(driveTrackIdPrefix)) {
      final fileId = videoId.substring(driveTrackIdPrefix.length);
      final headers = await GoogleDriveService.streamHeaders(fileId);
      if (requestId != _loadRequestId) return;
      await player.setAudioSource(
        AudioSource.uri(GoogleDriveService.streamUri(fileId), headers: headers),
        initialPosition: startAt,
        preload: true,
      );
      if (requestId != _loadRequestId) return;
      if (autoPlay) unawaited(player.play());
      return;
    }

    final localPath = resolveLocalPath?.call(videoId);
    if (localPath != null) {
      await player.setAudioSource(
        AudioSource.uri(Uri.file(localPath)),
        initialPosition: startAt,
      );
      if (requestId != _loadRequestId) return;
      if (autoPlay) unawaited(player.play());
      return;
    }

    final resolved = await _resolver.resolve(videoId);
    if (requestId != _loadRequestId) return;
    await _setYouTubeSource(
      resolved.audioUrls,
      position: startAt,
      autoPlay: autoPlay,
      requestId: requestId,
    );
  }

  Future<void> loadOnto(
    AudioPlayer target,
    Track track, {
    Duration startAt = Duration.zero,
  }) async {
    final videoId = track.videoId;
    if (videoId == null || videoId.isEmpty) return;

    if (videoId.startsWith(driveTrackIdPrefix)) {
      final fileId = videoId.substring(driveTrackIdPrefix.length);
      final headers = await GoogleDriveService.streamHeaders(fileId);
      await target.setAudioSource(
        AudioSource.uri(GoogleDriveService.streamUri(fileId), headers: headers),
        initialPosition: startAt,
        preload: true,
      );
      return;
    }

    final localPath = resolveLocalPath?.call(videoId);
    if (localPath != null) {
      await target.setAudioSource(
        AudioSource.uri(Uri.file(localPath)),
        initialPosition: startAt,
      );
      return;
    }

    debugPrint('[crossfade] loadOnto: resolving stream for $videoId');
    final resolveStopwatch = Stopwatch()..start();
    final resolved = await _resolver.resolve(videoId);
    debugPrint(
      '[crossfade] loadOnto: resolved in ${resolveStopwatch.elapsedMilliseconds}ms, ${resolved.audioUrls.length} candidate(s)',
    );
    Object? lastError;
    var candidateIndex = 0;
    for (final url in resolved.audioUrls) {
      candidateIndex++;
      debugPrint(
        '[crossfade] loadOnto: trying candidate $candidateIndex/${resolved.audioUrls.length}',
      );
      final candidateStopwatch = Stopwatch()..start();
      try {
        await target
            .setAudioSource(
              AudioSource.uri(url, headers: _youtubeHttpHeaders),
              initialPosition: startAt,
              preload: true,
            )
            .timeout(const Duration(seconds: 8));
        debugPrint(
          '[crossfade] loadOnto: candidate $candidateIndex succeeded in ${candidateStopwatch.elapsedMilliseconds}ms',
        );
        return;
      } catch (error) {
        debugPrint(
          '[crossfade] loadOnto: candidate $candidateIndex failed after ${candidateStopwatch.elapsedMilliseconds}ms: $error',
        );
        lastError = error;
      }
    }
    throw lastError ?? StateError('No playable audio candidates');
  }

  Future<void> reloadAfterStreamError(Track track) async {
    final videoId = track.videoId;
    if (videoId == null || videoId.isEmpty) return;
    final requestId = ++_loadRequestId;
    final resumeAt = player.position;
    _resolver.invalidate(videoId);
    final resolved = await _resolver.resolve(videoId, forceRefresh: true);
    if (requestId != _loadRequestId) return;
    await _setYouTubeSource(
      resolved.audioUrls,
      position: resumeAt,
      autoPlay: true,
      requestId: requestId,
    );
  }

  Future<void> _setYouTubeSource(
    List<Uri> candidates, {
    required Duration position,
    required bool autoPlay,
    required int requestId,
  }) async {
    Object? lastError;
    for (final url in candidates) {
      if (requestId != _loadRequestId) return;
      try {
        await player
            .setAudioSource(
              AudioSource.uri(url, headers: _youtubeHttpHeaders),
              initialPosition: position,
              preload: true,
            )
            .timeout(const Duration(seconds: 8));
        if (requestId != _loadRequestId) return;
        if (autoPlay) unawaited(player.play());
        return;
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? StateError('No playable audio candidates');
  }

  Future<void> prefetch(String videoId) async {
    try {
      await _resolver.resolve(videoId);
    } catch (_) {}
  }

  Future<Uri?> videoOnlyUrlFor(String videoId) =>
      _resolver.videoOnlyUrlFor(videoId);

  @override
  Future<void> play() async => onPlayRequested?.call();

  @override
  Future<void> pause() async => onPauseRequested?.call();

  @override
  Future<void> seek(Duration position) async => player.seek(position);

  @override
  Future<void> skipToNext() async => onNextRequested?.call();

  @override
  Future<void> skipToPrevious() async => onPreviousRequested?.call();

  @override
  Future<void> stop() async {
    await onStopRequested?.call();
    await player.stop();
    await super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    await player.stop();
    await super.stop();
  }

  Future<void> dispose() async {
    await _playerStateSub?.cancel();
    await _eventSub?.cancel();
    await player.dispose();
    _resolver.dispose();
  }
}
