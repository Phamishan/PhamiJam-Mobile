import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/services/youtube_service.dart';
import 'package:ytmusicapi_dart/navigation.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

class ChartsService {
  ChartsService._();

  static final Map<String, Playlist?> _cache = {};

  static Future<Playlist?> fetchTopPlaylist({
    required String countryCode,
    required String displayTitle,
    int targetSize = 50,
    String displaySubtitle = 'PhamiJam Playlists',
  }) async {
    final cacheKey = '$countryCode:$targetSize';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    Playlist? result;
    try {
      var tracks = <Track>[];
      try {
        final ytmusic = await YTMusic.create();
        final playlistId = await _resolveTopVideosPlaylistId(
          ytmusic,
          countryCode,
        );
        if (playlistId != null) {
          tracks = await YoutubeService.fetchPlaylistTracks(
            playlistId,
            maxItems: targetSize,
          );
        }
      } catch (_) {
        tracks = [];
      }

      if (tracks.length < targetSize) {
        try {
          final regional = await YoutubeService.fetchRegionalMusicChart(
            countryCode,
            maxResults: targetSize,
          );
          if (regional.length > tracks.length) tracks = regional;
        } catch (_) {}
      }

      if (tracks.length > targetSize) {
        tracks = tracks.take(targetSize).toList();
      }

      if (tracks.isNotEmpty) {
        result = Playlist(
          id: '',
          title: displayTitle,
          subtitle: displaySubtitle,
          thumbnailUrl: tracks.first.thumbnailUrl,
          tracks: tracks,
          isOwnedByUser: false,
        );
      }
    } catch (_) {
      result = null;
    }

    _cache[cacheKey] = result;
    return result;
  }

  static Future<String?> _resolveTopVideosPlaylistId(
    YTMusic ytmusic,
    String country,
  ) async {
    final body = <String, dynamic>{'browseId': 'FEmusic_charts'};
    if (country.isNotEmpty) {
      body['formData'] = {
        'selectedValues': [country],
      };
    }
    final response = await ytmusic.sendRequest('browse', body);
    final results =
        nav(response, [...SINGLE_COLUMN_TAB, ...SECTION_LIST]) as List;

    for (final section in results.skip(1)) {
      final contents = nav(section, CAROUSEL_CONTENTS, nullIfAbsent: true);
      if (contents is! List || contents.isEmpty) continue;
      final browseId = nav(contents.first, [
        MTRIR,
        ...TITLE,
        ...NAVIGATION_BROWSE_ID,
      ], nullIfAbsent: true);
      if (browseId is String && browseId.startsWith('VL')) {
        return browseId.substring(2);
      }
    }
    return null;
  }
}
