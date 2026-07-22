import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:provider/provider.dart';

Future<void> toggleTrackDownload(BuildContext context, Track track) async {
  final videoId = track.videoId;
  if (videoId == null || videoId.isEmpty) return;
  final downloads = context.read<DownloadsProvider>();

  if (downloads.isDownloaded(videoId)) {
    await downloads.remove(videoId);
    return;
  }

  await downloads.download(track);
  if (context.mounted && downloads.didFail(videoId)) {
    AppFlushbar.error(context, "Couldn't download '${track.title}'");
  }
}
