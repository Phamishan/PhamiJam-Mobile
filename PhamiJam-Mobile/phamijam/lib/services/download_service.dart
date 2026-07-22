import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/services/audio_stream_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

String formatDownloadSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class DownloadedTrack {
  final Track track;
  final String filePath;
  final int fileSizeBytes;
  final DateTime downloadedAt;

  const DownloadedTrack({
    required this.track,
    required this.filePath,
    required this.fileSizeBytes,
    required this.downloadedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': track.id,
    'title': track.title,
    'artist': track.artist,
    'thumbnailUrl': track.thumbnailUrl,
    'durationMs': track.duration.inMilliseconds,
    'videoId': track.videoId,
    'channelId': track.channelId,
    'filePath': filePath,
    'fileSizeBytes': fileSizeBytes,
    'downloadedAt': downloadedAt.millisecondsSinceEpoch,
  };

  static DownloadedTrack? fromJson(dynamic json) {
    if (json is! Map) return null;
    final videoId = json['videoId'];
    final filePath = json['filePath'];
    if (videoId is! String || videoId.isEmpty || filePath is! String) {
      return null;
    }
    return DownloadedTrack(
      track: Track(
        id: json['id'] is String ? json['id'] as String : videoId,
        title: json['title'] is String ? json['title'] as String : '',
        artist: json['artist'] is String ? json['artist'] as String : '',
        thumbnailUrl: json['thumbnailUrl'] is String
            ? json['thumbnailUrl'] as String
            : '',
        duration: Duration(
          milliseconds: json['durationMs'] is int
              ? json['durationMs'] as int
              : 0,
        ),
        videoId: videoId,
        channelId: json['channelId'] is String
            ? json['channelId'] as String
            : null,
      ),
      filePath: filePath,
      fileSizeBytes: json['fileSizeBytes'] is int
          ? json['fileSizeBytes'] as int
          : 0,
      downloadedAt: DateTime.fromMillisecondsSinceEpoch(
        json['downloadedAt'] is int ? json['downloadedAt'] as int : 0,
      ),
    );
  }
}

class DownloadsProvider extends ChangeNotifier {
  DownloadsProvider({AudioStreamResolver? resolver})
    : _resolver = resolver ?? AudioStreamResolver() {
    _load();
  }

  static const String _manifestKey = 'phamijam.downloads.manifest';

  final AudioStreamResolver _resolver;
  final Map<String, DownloadedTrack> _downloaded = {};
  final Map<String, double> _progress = {};
  final Set<String> _failed = {};
  final Map<String, http.Client> _activeClients = {};
  final Set<String> _cancelled = {};
  bool _stopBulkRequested = false;
  bool _loaded = false;

  bool get isReady => _loaded;
  int get totalTracks => _downloaded.length;

  int get totalSizeBytes =>
      _downloaded.values.fold(0, (sum, d) => sum + d.fileSizeBytes);

  List<DownloadedTrack> get all =>
      _downloaded.values.toList()
        ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));

  bool isDownloaded(String? videoId) =>
      videoId != null && _downloaded.containsKey(videoId);

  bool isDownloading(String? videoId) =>
      videoId != null && _progress.containsKey(videoId);

  double? progressFor(String? videoId) =>
      videoId == null ? null : _progress[videoId];

  bool didFail(String? videoId) => videoId != null && _failed.contains(videoId);

  bool isCancellable(String? videoId) =>
      videoId != null && _activeClients.containsKey(videoId);

  String? localPathFor(String videoId) => _downloaded[videoId]?.filePath;

  Future<void> cancelDownload(String videoId) async {
    final client = _activeClients[videoId];
    if (client == null) return;
    _cancelled.add(videoId);
    client.close();
  }

  void cancelAllDownloads() {
    _stopBulkRequested = true;
    for (final videoId in _progress.keys.toList()) {
      cancelDownload(videoId);
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_manifestKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded) {
            final downloaded = DownloadedTrack.fromJson(entry);
            final videoId = downloaded?.track.videoId;
            if (downloaded != null && videoId != null) {
              _downloaded[videoId] = downloaded;
            }
          }
        }
      } catch (error) {
        debugPrint('DownloadsProvider: failed to parse manifest: $error');
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _saveManifest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _manifestKey,
      jsonEncode(_downloaded.values.map((d) => d.toJson()).toList()),
    );
  }

  Future<Directory> _downloadsDir() async {
    final dir = await getApplicationSupportDirectory();
    final downloads = Directory('${dir.path}/downloads');
    if (!downloads.existsSync()) {
      downloads.createSync(recursive: true);
    }
    return downloads;
  }

  Future<void> download(Track track) async {
    final videoId = track.videoId;
    if (videoId == null || videoId.isEmpty) return;
    if (isDownloaded(videoId) || isDownloading(videoId)) return;

    _failed.remove(videoId);
    _cancelled.remove(videoId);
    _progress[videoId] = 0;
    notifyListeners();

    final client = http.Client();
    _activeClients[videoId] = client;
    File? partialFile;
    try {
      final resolved = await _resolver.resolve(videoId);
      final dir = await _downloadsDir();
      final file = File('${dir.path}/$videoId.m4a');
      partialFile = file;

      final response = await client.send(
        http.Request('GET', resolved.audioUrl),
      );
      final total = response.contentLength ?? 0;
      var received = 0;

      final sink = file.openWrite();
      await response.stream
          .map((chunk) {
            received += chunk.length;
            if (total > 0) {
              _progress[videoId] = received / total;
              notifyListeners();
            }
            return chunk;
          })
          .pipe(sink);
      await sink.close();

      _downloaded[videoId] = DownloadedTrack(
        track: track,
        filePath: file.path,
        fileSizeBytes: await file.length(),
        downloadedAt: DateTime.now(),
      );
      await _saveManifest();
    } catch (error) {
      final wasCancelled = _cancelled.remove(videoId);
      if (wasCancelled) {
        try {
          if (partialFile != null && partialFile.existsSync()) {
            partialFile.deleteSync();
          }
        } catch (_) {}
      } else {
        debugPrint('DownloadsProvider: download failed for $videoId: $error');
        _failed.add(videoId);
      }
    } finally {
      client.close();
      _activeClients.remove(videoId);
      _progress.remove(videoId);
      notifyListeners();
    }
  }

  Future<void> downloadPlaylist(List<Track> tracks) async {
    _stopBulkRequested = false;
    for (final track in tracks) {
      if (_stopBulkRequested) break;
      final videoId = track.videoId;
      if (videoId == null || videoId.isEmpty) continue;
      if (isDownloaded(videoId)) continue;
      await download(track);
    }
  }

  Future<void> remove(String videoId) async {
    final entry = _downloaded.remove(videoId);
    if (entry != null) {
      try {
        final file = File(entry.filePath);
        if (file.existsSync()) file.deleteSync();
      } catch (error) {
        debugPrint('DownloadsProvider: failed to delete file: $error');
      }
    }
    await _saveManifest();
    notifyListeners();
  }

  Future<void> clearAll() async {
    final entries = _downloaded.values.toList();
    _downloaded.clear();
    for (final entry in entries) {
      try {
        final file = File(entry.filePath);
        if (file.existsSync()) file.deleteSync();
      } catch (error) {
        debugPrint('DownloadsProvider: failed to delete file: $error');
      }
    }
    await _saveManifest();
    notifyListeners();
  }
}
