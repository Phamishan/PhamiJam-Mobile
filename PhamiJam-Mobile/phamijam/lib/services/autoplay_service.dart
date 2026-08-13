import 'package:flutter/foundation.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/pages/artist_page.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

class AutoplayService {
  AutoplayService._();

  static Future<List<Track>> fetchAutoplayContinuation(
    YTMusic ytmusic,
    String seedVideoId, {
    Set<String> excludeVideoIds = const {},
    int limit = 10,
  }) async {
    try {
      final result = await ytmusic.getWatchPlaylist(
        videoId: seedVideoId,
        radio: true,
        limit: 25,
      );
      final tracks = result['tracks'];
      if (tracks is! List) return [];

      final continuation = <Track>[];
      for (final item in tracks) {
        if (item is! Map<String, dynamic>) continue;
        final videoId = item['videoId'];
        if (videoId is! String ||
            videoId.isEmpty ||
            videoId == seedVideoId ||
            excludeVideoIds.contains(videoId)) {
          continue;
        }
        continuation.add(
          ytSongToTrack(
            item,
            fallbackArtistName: 'YouTube Music',
            fallbackArtistId: '',
          ),
        );
        if (continuation.length >= limit) break;
      }
      return continuation;
    } catch (error) {
      debugPrint('AutoplayService: fetchAutoplayContinuation failed: $error');
      return [];
    }
  }
}
