import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:phamijam/models/track.dart';
import 'package:phamijam/services/drive_duration_cache_service.dart';
import 'package:phamijam/services/drive_folder_service.dart';

const String _logTag = 'GoogleDriveService';
const String _driveApiBase = 'https://www.googleapis.com/drive/v3';
const String driveTrackIdPrefix = 'drive:';

class GoogleDriveApiException implements Exception {
  final String message;
  GoogleDriveApiException(this.message);

  @override
  String toString() => message;
}

class GoogleDriveService {
  GoogleDriveService._();

  static String get _apiKey => dotenv.env['DRIVE_API_KEY'] ?? '';

  static Future<List<Track>?> listAudioFiles() async {
    final folderId = await DriveFolderService.getFolderId();
    if (folderId == null) return null;

    final uri = Uri.parse('$_driveApiBase/files').replace(
      queryParameters: {
        'q':
            "'$folderId' in parents and trashed = false and mimeType contains 'audio/'",
        'fields': 'files(id,name,createdTime)',
        'pageSize': '200',
        'key': _apiKey,
      },
    );

    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '$_logTag: list files failed (${response.statusCode}): ${response.body}',
      );
      throw GoogleDriveApiException(
        'Failed to list Google Drive folder (${response.statusCode}).',
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final files = (payload['files'] as List? ?? const [])
        .whereType<Map<String, dynamic>>();

    return Future.wait(files.map(_trackFromFile));
  }

  static Future<Track> _trackFromFile(Map<String, dynamic> file) async {
    final id = file['id'] as String? ?? '';
    final name = file['name'] as String? ?? 'Unknown song';
    final createdTime = file['createdTime'] as String?;
    final parsed = _titleArtistFromFileName(_stripExtension(name));
    final cachedDuration = await DriveDurationCacheService.getDuration(id);

    return Track(
      id: 'drive-$id',
      title: parsed.title,
      artist: parsed.artist,
      thumbnailUrl: '',
      duration: cachedDuration ?? Duration.zero,
      videoId: '$driveTrackIdPrefix$id',
      addedAt: createdTime != null ? DateTime.tryParse(createdTime) : null,
    );
  }

  static ({String title, String artist}) _titleArtistFromFileName(
    String nameWithoutExtension,
  ) {
    final separatorIndex = nameWithoutExtension.indexOf(' - ');
    if (separatorIndex > 0) {
      final artist = nameWithoutExtension.substring(0, separatorIndex).trim();
      final title = nameWithoutExtension.substring(separatorIndex + 3).trim();
      if (artist.isNotEmpty && title.isNotEmpty) {
        return (title: title, artist: artist);
      }
    }
    return (title: nameWithoutExtension, artist: 'Unknown artist');
  }

  static String _stripExtension(String fileName) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0) return fileName;
    return fileName.substring(0, dotIndex);
  }

  static Future<bool> canAccessFolder(String folderId) async {
    final uri = Uri.parse(
      '$_driveApiBase/files/$folderId',
    ).replace(queryParameters: {'fields': 'id,mimeType', 'key': _apiKey});
    try {
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return payload['mimeType'] == 'application/vnd.google-apps.folder';
    } catch (error) {
      debugPrint('$_logTag: folder access check failed: $error');
      return false;
    }
  }

  static Future<Map<String, String>> streamHeaders(String fileId) async => {};

  static Uri streamUri(String fileId) => Uri.parse(
    '$_driveApiBase/files/$fileId',
  ).replace(queryParameters: {'alt': 'media', 'key': _apiKey});
}
