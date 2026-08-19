import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class ResolvedStreams {
  const ResolvedStreams({
    required this.audioUrls,
    required this.videoOnlyUrl,
    required this.expiresAt,
  });

  final List<Uri> audioUrls;
  final Uri? videoOnlyUrl;
  final DateTime expiresAt;

  Uri get audioUrl => audioUrls.first;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class StreamResolutionException implements Exception {
  StreamResolutionException(this.videoId, this.cause);
  final String videoId;
  final Object? cause;

  @override
  String toString() =>
      'StreamResolutionException(videoId: $videoId, cause: $cause)';
}

class AudioStreamResolver {
  AudioStreamResolver({YoutubeExplode? client})
    : _yt = client ?? YoutubeExplode();

  final YoutubeExplode _yt;
  static final _ytClients = [YoutubeApiClient.androidSdkless];
  final Map<String, ResolvedStreams> _cache = {};
  final Map<String, Future<ResolvedStreams>> _inflight = {};

  Future<void> _resolveQueue = Future.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final previous = _resolveQueue;
    final completer = Completer<void>();
    _resolveQueue = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }

  Future<ResolvedStreams> resolve(String videoId, {bool forceRefresh = false}) {
    final cached = _cache[videoId];
    if (!forceRefresh && cached != null && !cached.isExpired) {
      return Future.value(cached);
    }
    final existing = _inflight[videoId];
    if (existing != null) return existing;

    final future = _serialized(() => _resolveUncached(videoId)).whenComplete(
      () {
        _inflight.remove(videoId);
      },
    );
    _inflight[videoId] = future;
    return future;
  }

  Future<ResolvedStreams> _resolveUncached(String videoId) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final manifest = await _getMergedManifest(
          videoId,
          requireWatchPage: attempt > 0,
        );
        final resolved = _pickStreams(manifest);
        _cache[videoId] = resolved;
        return resolved;
      } catch (error) {
        lastError = error;
        if (attempt == 0) {
          await Future.delayed(const Duration(milliseconds: 400));
        }
      }
    }
    throw StreamResolutionException(videoId, lastError);
  }

  Future<StreamManifest> _getMergedManifest(
    String videoId, {
    required bool requireWatchPage,
  }) async {
    final completer = Completer<StreamManifest?>();
    var remaining = _ytClients.length;
    for (final client in _ytClients) {
      unawaited(
        _tryGetManifest(videoId, client, requireWatchPage).then((manifest) {
          remaining--;
          if (completer.isCompleted) return;
          if (manifest != null) {
            completer.complete(manifest);
          } else if (remaining == 0) {
            completer.complete(null);
          }
        }),
      );
    }
    final manifest = await completer.future;
    if (manifest == null) {
      throw StateError(
        'No client could resolve a stream manifest for $videoId',
      );
    }
    return manifest;
  }

  Future<StreamManifest?> _tryGetManifest(
    String videoId,
    YoutubeApiClient client,
    bool requireWatchPage,
  ) async {
    try {
      return await _yt.videos.streams.getManifest(
        videoId,
        ytClients: [client],
        requireWatchPage: requireWatchPage,
      );
    } catch (_) {
      return null;
    }
  }

  List<Uri> _pickAudioCandidates(StreamManifest manifest) {
    final mp4Audio = manifest.audioOnly
        .where((s) => s.container == StreamContainer.mp4)
        .toList()
        .sortByBitrate();
    final otherAudio = manifest.audioOnly
        .where((s) => s.container != StreamContainer.mp4)
        .toList()
        .sortByBitrate();
    final muxed = manifest.muxed.toList().sortByBitrate();

    final urls = [
      ...muxed.map((s) => s.url),
      ...mp4Audio.map((s) => s.url),
      ...otherAudio.map((s) => s.url),
    ];
    if (urls.isEmpty) {
      throw StateError('No playable audio streams in manifest');
    }
    return urls;
  }

  ResolvedStreams _pickStreams(StreamManifest manifest) {
    final audioUrls = _pickAudioCandidates(manifest);

    final mp4VideoCandidates = manifest.videoOnly
        .where((s) => s.container == StreamContainer.mp4)
        .where((s) => s.videoResolution.height <= 480)
        .toList()
        .sortByBitrate();
    final anyVideoCandidates = manifest.videoOnly
        .where((s) => s.videoResolution.height <= 480)
        .toList()
        .sortByBitrate();
    final videoCandidates = mp4VideoCandidates.isNotEmpty
        ? mp4VideoCandidates
        : anyVideoCandidates;
    final video = videoCandidates.isNotEmpty
        ? videoCandidates.first
        : (manifest.videoOnly.isNotEmpty
              ? manifest.videoOnly.sortByBitrate().last
              : null);

    return ResolvedStreams(
      audioUrls: audioUrls,
      videoOnlyUrl: video?.url,
      expiresAt: DateTime.now().add(const Duration(hours: 4)),
    );
  }

  Future<Uri?> videoOnlyUrlFor(String videoId) async {
    final resolved = await resolve(videoId);
    return resolved.videoOnlyUrl;
  }

  void invalidate(String videoId) => _cache.remove(videoId);

  void dispose() => _yt.close();
}
