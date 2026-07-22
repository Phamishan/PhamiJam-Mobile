import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/services/audio_stream_resolver.dart';

class PhamiJamAudioHandler extends BaseAudioHandler {
  PhamiJamAudioHandler({AudioStreamResolver? resolver})
    : _resolver = resolver ?? AudioStreamResolver() {
    _wirePlayerStreams();
  }

  final AudioStreamResolver _resolver;
  final AudioPlayer player = AudioPlayer();

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
      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            state.playing ? MediaControl.pause : MediaControl.play,
            MediaControl.skipToNext,
            MediaControl.stop,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          androidCompactActionIndices: const [0, 1, 2],
          processingState: _mapProcessingState(state.processingState),
          playing: state.playing,
          updatePosition: player.position,
          bufferedPosition: player.bufferedPosition,
          speed: player.speed,
        ),
      );
    });

    _eventSub = player.playbackEventStream.listen((_) {}, onError: (_, _) {});
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
    await player.setAudioSource(
      AudioSource.uri(resolved.audioUrl),
      initialPosition: startAt,
    );
    if (requestId != _loadRequestId) return;
    if (autoPlay) unawaited(player.play());
  }

  Future<void> reloadAfterStreamError(Track track) async {
    final videoId = track.videoId;
    if (videoId == null || videoId.isEmpty) return;
    final requestId = ++_loadRequestId;
    final resumeAt = player.position;
    _resolver.invalidate(videoId);
    final resolved = await _resolver.resolve(videoId, forceRefresh: true);
    if (requestId != _loadRequestId) return;
    await player.setAudioSource(
      AudioSource.uri(resolved.audioUrl),
      initialPosition: resumeAt,
    );
    if (requestId != _loadRequestId) return;
    unawaited(player.play());
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
