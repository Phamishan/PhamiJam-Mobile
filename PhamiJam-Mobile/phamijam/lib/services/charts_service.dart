import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/services/youtube_service.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

class ChartsService {
  ChartsService._();

  static final Map<String, Playlist?> _cache = {};

  static Future<Playlist?> fetchTopPlaylist({
    required String countryCode,
    required String displayTitle,
    String displaySubtitle = 'PhamiJam Playlists',
  }) async {
    if (_cache.containsKey(countryCode)) return _cache[countryCode];

    Playlist? result;
    try {
      final ytmusic = await YTMusic.create();
      final charts = await ytmusic.getCharts(country: countryCode);
      final videos = charts['videos'];
      if (videos is List && videos.isNotEmpty) {
        final playlistId = (videos.first as Map)['playlistId'] as String?;
        if (playlistId != null && playlistId.isNotEmpty) {
          final playlist = await YoutubeService.fetchPlaylistById(playlistId);
          if (playlist != null) {
            result = playlist.copyWith(
              title: displayTitle,
              subtitle: displaySubtitle,
            );
          }
        }
      }
    } catch (_) {
      result = null;
    }

    _cache[countryCode] = result;
    return result;
  }
}
