import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/models/track.dart';
import 'package:share_plus/share_plus.dart';

const String shareBaseHost = 'phamijam-share.phamijam.workers.dev';

class ShareLinkService {
  ShareLinkService._();

  static Uri buildSongUrl(String videoId) =>
      Uri.https(shareBaseHost, '/s/$videoId');

  static Uri buildPlaylistUrl(String playlistId) =>
      Uri.https(shareBaseHost, '/p/$playlistId');

  static Future<void> shareTrack(BuildContext context, Track track) async {
    final videoId = track.videoId;
    if (videoId == null || videoId.isEmpty) return;
    await _share(
      context,
      buildSongUrl(videoId),
      subject: track.title,
    );
  }

  static Future<void> sharePlaylist(
    BuildContext context,
    Playlist playlist,
  ) async {
    if (playlist.id.isEmpty) return;
    await _share(
      context,
      buildPlaylistUrl(playlist.id),
      subject: playlist.title,
    );
  }

  static Future<void> _share(
    BuildContext context,
    Uri url, {
    required String subject,
  }) async {
    try {
      final result = await SharePlus.instance.share(
        ShareParams(uri: url, subject: subject),
      );
      if (result.status == ShareResultStatus.unavailable && context.mounted) {
        await _copyToClipboard(context, url);
      }
    } catch (_) {
      if (context.mounted) await _copyToClipboard(context, url);
    }
  }

  static Future<void> _copyToClipboard(BuildContext context, Uri url) async {
    await Clipboard.setData(ClipboardData(text: url.toString()));
    if (context.mounted) {
      AppFlushbar.success(context, 'Link copied to clipboard');
    }
  }
}
