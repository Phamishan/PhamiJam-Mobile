import 'dart:async';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class ResolvedStreams {
  const ResolvedStreams({
    required this.audioUrl,
    required this.videoOnlyUrl,
    required this.expiresAt,
  });

  final Uri audioUrl;
  final Uri? videoOnlyUrl;
  final DateTime expiresAt;

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
  static final _ytClients = [YoutubeApiClient.androidVr, YoutubeApiClient.ios];
  final Map<String, ResolvedStreams> _cache = {};
  final Map<String, Future<ResolvedStreams>> _inflight = {};

  Future<ResolvedStreams> resolve(String videoId, {bool forceRefresh = false}) {
    final cached = _cache[videoId];
    if (!forceRefresh && cached != null && !cached.isExpired) {
      return Future.value(cached);
    }
    final existing = _inflight[videoId];
    if (existing != null) return existing;

    final future = _resolveUncached(videoId).whenComplete(() {
      _inflight.remove(videoId);
    });
    _inflight[videoId] = future;
    return future;
  }

  Future<ResolvedStreams> _resolveUncached(String videoId) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final manifest = await _yt.videos.streams.getManifest(
          videoId,
          ytClients: _ytClients,
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

  ResolvedStreams _pickStreams(StreamManifest manifest) {
    if (manifest.audioOnly.isEmpty) {
      throw StateError('No audio-only streams in manifest');
    }
    final mp4AudioCandidates = manifest.audioOnly
        .where((s) => s.container == StreamContainer.mp4)
        .toList();
    final audio = mp4AudioCandidates.isNotEmpty
        ? mp4AudioCandidates.withHighestBitrate()
        : manifest.audioOnly.withHighestBitrate();

    final videoCandidates = manifest.videoOnly
        .where((s) => s.videoResolution.height <= 480)
        .toList()
        .sortByBitrate();
    final video = videoCandidates.isNotEmpty
        ? videoCandidates.first
        : (manifest.videoOnly.isNotEmpty
              ? manifest.videoOnly.sortByBitrate().last
              : null);

    return ResolvedStreams(
      audioUrl: audio.url,
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
