import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:phamijam/models/track.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SavedPlaybackState {
  final List<Track> queue;
  final List<Track> originalQueue;
  final int queueIndex;
  final Duration position;
  final bool shuffle;
  final String repeatMode;

  const SavedPlaybackState({
    required this.queue,
    required this.originalQueue,
    required this.queueIndex,
    required this.position,
    required this.shuffle,
    required this.repeatMode,
  });
}

class PlaybackStateService {
  PlaybackStateService._();

  static const String _key = 'phamijam.playback_state';
  static const String _volumeKey = 'phamijam.playback_volume';

  static Future<void> saveVolume(double volume) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volumeKey, volume);
  }

  static Future<double?> loadVolume() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_volumeKey);
  }

  static Map<String, dynamic> _trackToJson(Track track) => {
    'id': track.id,
    'title': track.title,
    'artist': track.artist,
    'thumbnailUrl': track.thumbnailUrl,
    'durationMs': track.duration.inMilliseconds,
    'videoId': track.videoId,
    'channelId': track.channelId,
    'playlistItemId': track.playlistItemId,
  };

  static Track? _trackFromJson(dynamic json) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    final artist = json['artist'];
    final thumbnailUrl = json['thumbnailUrl'];
    if (id is! String ||
        title is! String ||
        artist is! String ||
        thumbnailUrl is! String) {
      return null;
    }
    return Track(
      id: id,
      title: title,
      artist: artist,
      thumbnailUrl: thumbnailUrl,
      duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
      videoId: json['videoId'] as String?,
      channelId: json['channelId'] as String?,
      playlistItemId: json['playlistItemId'] as String?,
    );
  }

  static Future<void> save({
    required List<Track> queue,
    required List<Track> originalQueue,
    required int queueIndex,
    required Duration position,
    required bool shuffle,
    required String repeatMode,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (queue.isEmpty || queueIndex < 0 || queueIndex >= queue.length) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setString(
      _key,
      jsonEncode({
        'queue': queue.map(_trackToJson).toList(),
        'originalQueue': originalQueue.map(_trackToJson).toList(),
        'queueIndex': queueIndex,
        'positionMs': position.inMilliseconds,
        'shuffle': shuffle,
        'repeatMode': repeatMode,
      }),
    );
  }

  static Future<SavedPlaybackState?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final queue = ((decoded['queue'] as List?) ?? [])
          .map(_trackFromJson)
          .whereType<Track>()
          .toList();
      if (queue.isEmpty) return null;

      final originalQueue = ((decoded['originalQueue'] as List?) ?? [])
          .map(_trackFromJson)
          .whereType<Track>()
          .toList();

      final queueIndex = decoded['queueIndex'] as int? ?? 0;
      if (queueIndex < 0 || queueIndex >= queue.length) return null;

      return SavedPlaybackState(
        queue: queue,
        originalQueue: originalQueue.isEmpty ? queue : originalQueue,
        queueIndex: queueIndex,
        position: Duration(milliseconds: decoded['positionMs'] as int? ?? 0),
        shuffle: decoded['shuffle'] as bool? ?? false,
        repeatMode: decoded['repeatMode'] as String? ?? 'off',
      );
    } catch (error) {
      debugPrint('PlaybackStateService: failed to parse saved state: $error');
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
