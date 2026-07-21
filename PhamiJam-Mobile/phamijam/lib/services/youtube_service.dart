import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:phamijam/models/channel.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/services/google_auth_service.dart';

const String _logTag = 'YoutubeService';
const String _baseUrl = 'https://www.googleapis.com/youtube/v3';

class YoutubeApiException implements Exception {
  final String message;
  YoutubeApiException(this.message);

  @override
  String toString() => message;
}

class YoutubeService {
  YoutubeService._();

  static Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final token = await GoogleAuthService.ensureAccessToken();
    if (token == null || token.isEmpty) {
      throw YoutubeApiException('Not signed in to YouTube.');
    }

    final uri = Uri.parse('$_baseUrl/$path').replace(queryParameters: query);
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '$_logTag: GET $path failed (${response.statusCode}): ${response.body}',
      );
      throw YoutubeApiException(
        'YouTube request failed (${response.statusCode}).',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, String> query,
    Map<String, dynamic> body,
  ) async {
    final token = await GoogleAuthService.ensureAccessToken();
    if (token == null || token.isEmpty) {
      throw YoutubeApiException('Not signed in to YouTube.');
    }

    final uri = Uri.parse('$_baseUrl/$path').replace(queryParameters: query);
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '$_logTag: POST $path failed (${response.statusCode}): ${response.body}',
      );
      throw YoutubeApiException(
        'YouTube request failed (${response.statusCode}).',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> _put(
    String path,
    Map<String, String> query,
    Map<String, dynamic> body,
  ) async {
    final token = await GoogleAuthService.ensureAccessToken();
    if (token == null || token.isEmpty) {
      throw YoutubeApiException('Not signed in to YouTube.');
    }

    final uri = Uri.parse('$_baseUrl/$path').replace(queryParameters: query);
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '$_logTag: PUT $path failed (${response.statusCode}): ${response.body}',
      );
      throw YoutubeApiException(
        'YouTube request failed (${response.statusCode}).',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<void> _delete(String path, Map<String, String> query) async {
    final token = await GoogleAuthService.ensureAccessToken();
    if (token == null || token.isEmpty) {
      throw YoutubeApiException('Not signed in to YouTube.');
    }

    final uri = Uri.parse('$_baseUrl/$path').replace(queryParameters: query);
    final response = await http.delete(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '$_logTag: DELETE $path failed (${response.statusCode}): ${response.body}',
      );
      throw YoutubeApiException(
        'YouTube request failed (${response.statusCode}).',
      );
    }
  }

  static String _bestThumbnail(Map<String, dynamic>? snippet) {
    final thumbnails = snippet?['thumbnails'] as Map<String, dynamic>?;
    if (thumbnails == null) return '';
    for (final key in ['maxres', 'standard', 'high', 'medium', 'default']) {
      final thumb = thumbnails[key] as Map<String, dynamic>?;
      final url = thumb?['url'] as String?;
      if (url != null && url.isNotEmpty) return url;
    }
    return '';
  }

  static Duration _parseIsoDuration(String iso) {
    final match = RegExp(
      r'^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$',
    ).firstMatch(iso);
    if (match == null) return Duration.zero;
    final hours = int.tryParse(match.group(1) ?? '') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '') ?? 0;
    return Duration(hours: hours, minutes: minutes, seconds: seconds);
  }

  static Future<List<Playlist>> fetchMyPlaylists() async {
    final playlists = <Playlist>[];
    String? pageToken;

    do {
      final data = await _get('playlists', {
        'part': 'snippet,contentDetails',
        'mine': 'true',
        'maxResults': '50',
        'pageToken': ?pageToken,
      });

      for (final item in (data['items'] as List? ?? [])) {
        final map = item as Map<String, dynamic>;
        final snippet = map['snippet'] as Map<String, dynamic>?;
        final contentDetails = map['contentDetails'] as Map<String, dynamic>?;
        final itemCount = (contentDetails?['itemCount'] as num?)?.toInt() ?? 0;
        final description = (snippet?['description'] as String? ?? '').trim();

        playlists.add(
          Playlist(
            id: map['id'] as String,
            title: snippet?['title'] as String? ?? 'Untitled playlist',
            subtitle: description.isEmpty ? '$itemCount videos' : description,
            thumbnailUrl: _bestThumbnail(snippet),
            itemCount: itemCount,
          ),
        );
      }

      pageToken = data['nextPageToken'] as String?;
    } while (pageToken != null);

    return playlists;
  }

  static Future<List<Track>> searchVideos(
    String query, {
    int maxResults = 25,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final data = await _get('search', {
      'part': 'snippet',
      'type': 'video',
      'q': trimmed,
      'maxResults': '$maxResults',
    });

    final rawResults = <_RawSearchResult>[];
    for (final item in (data['items'] as List? ?? [])) {
      final map = item as Map<String, dynamic>;
      final videoId =
          (map['id'] as Map<String, dynamic>?)?['videoId'] as String?;
      if (videoId == null || videoId.isEmpty) continue;

      final snippet = map['snippet'] as Map<String, dynamic>?;
      rawResults.add(
        _RawSearchResult(
          videoId: videoId,
          title: snippet?['title'] as String? ?? '',
          artist: snippet?['channelTitle'] as String? ?? 'YouTube',
          channelId: snippet?['channelId'] as String?,
          thumbnailUrl: _bestThumbnail(snippet),
        ),
      );
    }

    final durations = await _fetchDurations(
      rawResults.map((e) => e.videoId).toList(),
    );

    return [
      for (final item in rawResults)
        Track(
          id: 'search-${item.videoId}',
          title: item.title,
          artist: item.artist,
          thumbnailUrl: item.thumbnailUrl,
          duration: durations[item.videoId] ?? Duration.zero,
          videoId: item.videoId,
          channelId: item.channelId,
        ),
    ];
  }

  static Future<void> addVideoToPlaylist(
    String playlistId,
    String videoId,
  ) async {
    await _post(
      'playlistItems',
      {'part': 'snippet'},
      {
        'snippet': {
          'playlistId': playlistId,
          'resourceId': {'kind': 'youtube#video', 'videoId': videoId},
        },
      },
    );
  }

  static Future<Playlist> createPlaylist(
    String title, {
    String description = '',
    String privacyStatus = 'private',
  }) async {
    final data = await _post(
      'playlists',
      {'part': 'snippet,status'},
      {
        'snippet': {
          'title': title,
          if (description.isNotEmpty) 'description': description,
        },
        'status': {'privacyStatus': privacyStatus},
      },
    );

    final snippet = data['snippet'] as Map<String, dynamic>?;
    return Playlist(
      id: data['id'] as String,
      title: snippet?['title'] as String? ?? title,
      subtitle: description.isEmpty ? '0 videos' : description,
      thumbnailUrl: _bestThumbnail(snippet),
      itemCount: 0,
    );
  }

  static Future<void> updatePlaylist(
    String playlistId, {
    required String title,
    required String description,
  }) async {
    await _put(
      'playlists',
      {'part': 'snippet'},
      {
        'id': playlistId,
        'snippet': {'title': title, 'description': description},
      },
    );
  }

  static Future<void> deletePlaylist(String playlistId) async {
    await _delete('playlists', {'id': playlistId});
  }

  static Future<String?> fetchLikedVideosPlaylistId() async {
    final data = await _get('channels', {
      'part': 'contentDetails',
      'mine': 'true',
    });

    final items = data['items'] as List? ?? [];
    if (items.isEmpty) return null;

    final contentDetails =
        (items.first as Map<String, dynamic>)['contentDetails']
            as Map<String, dynamic>?;
    final relatedPlaylists =
        contentDetails?['relatedPlaylists'] as Map<String, dynamic>?;
    return relatedPlaylists?['likes'] as String?;
  }

  static Future<Channel?> fetchChannelInfo(String channelId) async {
    final data = await _get('channels', {
      'part': 'snippet,statistics',
      'id': channelId,
    });

    final items = data['items'] as List? ?? [];
    if (items.isEmpty) return null;

    final map = items.first as Map<String, dynamic>;
    final snippet = map['snippet'] as Map<String, dynamic>?;
    final statistics = map['statistics'] as Map<String, dynamic>?;
    final hiddenSubscriberCount = statistics?['hiddenSubscriberCount'] == true;

    return Channel(
      id: channelId,
      name: snippet?['title'] as String? ?? 'Unknown artist',
      thumbnailUrl: _bestThumbnail(snippet),
      subscriberCount: hiddenSubscriberCount
          ? ''
          : (statistics?['subscriberCount'] as String?) ?? '',
      description: (snippet?['description'] as String? ?? '').trim(),
    );
  }

  static Future<String?> _fetchUploadsPlaylistId(String channelId) async {
    final data = await _get('channels', {
      'part': 'contentDetails',
      'id': channelId,
    });

    final items = data['items'] as List? ?? [];
    if (items.isEmpty) return null;

    final contentDetails =
        (items.first as Map<String, dynamic>)['contentDetails']
            as Map<String, dynamic>?;
    final relatedPlaylists =
        contentDetails?['relatedPlaylists'] as Map<String, dynamic>?;
    return relatedPlaylists?['uploads'] as String?;
  }

  static Future<List<Track>> fetchChannelVideos(
    String channelId, {
    int maxItems = 25,
  }) async {
    final uploadsPlaylistId = await _fetchUploadsPlaylistId(channelId);
    if (uploadsPlaylistId == null || uploadsPlaylistId.isEmpty) return [];
    return fetchPlaylistTracks(uploadsPlaylistId, maxItems: maxItems);
  }

  static Future<List<Track>> fetchPlaylistTracks(
    String playlistId, {
    int maxItems = 200,
  }) async {
    final rawItems = <_RawPlaylistItem>[];
    String? pageToken;

    do {
      final data = await _get('playlistItems', {
        'part': 'snippet,contentDetails',
        'playlistId': playlistId,
        'maxResults': '50',
        'pageToken': ?pageToken,
      });

      for (final item in (data['items'] as List? ?? [])) {
        final map = item as Map<String, dynamic>;
        final snippet = map['snippet'] as Map<String, dynamic>?;
        final contentDetails = map['contentDetails'] as Map<String, dynamic>?;
        final videoId =
            contentDetails?['videoId'] as String? ??
            (snippet?['resourceId'] as Map<String, dynamic>?)?['videoId']
                as String?;
        if (videoId == null || videoId.isEmpty) continue;

        final title = snippet?['title'] as String? ?? '';
        if (title == 'Deleted video' || title == 'Private video') continue;

        rawItems.add(
          _RawPlaylistItem(
            playlistItemId: '$playlistId-$videoId',
            apiItemId: map['id'] as String?,
            videoId: videoId,
            title: title,
            artist:
                snippet?['videoOwnerChannelTitle'] as String? ??
                snippet?['channelTitle'] as String? ??
                'YouTube',
            channelId: snippet?['videoOwnerChannelId'] as String?,
            thumbnailUrl: _bestThumbnail(snippet),
          ),
        );
      }

      pageToken = rawItems.length >= maxItems
          ? null
          : data['nextPageToken'] as String?;
    } while (pageToken != null);

    final bounded = rawItems.take(maxItems).toList();
    final durations = await _fetchDurations(
      bounded.map((e) => e.videoId).toList(),
    );

    return [
      for (final item in bounded)
        Track(
          id: item.playlistItemId,
          title: item.title,
          artist: item.artist,
          thumbnailUrl: item.thumbnailUrl,
          duration: durations[item.videoId] ?? Duration.zero,
          videoId: item.videoId,
          channelId: item.channelId,
          playlistItemId: item.apiItemId,
        ),
    ];
  }

  static Future<void> removeVideoFromPlaylist(String playlistItemId) async {
    await _delete('playlistItems', {'id': playlistItemId});
  }

  static Future<Map<String, Duration>> _fetchDurations(
    List<String> videoIds,
  ) async {
    final chunks = <List<String>>[];
    for (var i = 0; i < videoIds.length; i += 50) {
      final chunk = videoIds.sublist(i, (i + 50).clamp(0, videoIds.length));
      if (chunk.isNotEmpty) chunks.add(chunk);
    }
    if (chunks.isEmpty) return {};

    final responses = await Future.wait(
      chunks.map(
        (chunk) =>
            _get('videos', {'part': 'contentDetails', 'id': chunk.join(',')}),
      ),
    );

    final durations = <String, Duration>{};
    for (final data in responses) {
      for (final item in (data['items'] as List? ?? [])) {
        final map = item as Map<String, dynamic>;
        final iso =
            (map['contentDetails'] as Map<String, dynamic>?)?['duration']
                as String?;
        if (iso == null) continue;
        durations[map['id'] as String] = _parseIsoDuration(iso);
      }
    }
    return durations;
  }
}

class _RawSearchResult {
  final String videoId;
  final String title;
  final String artist;
  final String? channelId;
  final String thumbnailUrl;

  _RawSearchResult({
    required this.videoId,
    required this.title,
    required this.artist,
    this.channelId,
    required this.thumbnailUrl,
  });
}

class _RawPlaylistItem {
  final String playlistItemId;
  final String? apiItemId;
  final String videoId;
  final String title;
  final String artist;
  final String? channelId;
  final String thumbnailUrl;

  _RawPlaylistItem({
    required this.playlistItemId,
    this.apiItemId,
    required this.videoId,
    required this.title,
    required this.artist,
    this.channelId,
    required this.thumbnailUrl,
  });
}
