import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:provider/provider.dart';

Future<void> togglePlaylistPin(BuildContext context, Playlist playlist) async {
  final wasPinned = playlist.isPinned;
  try {
    await context.read<LibraryProvider>().togglePin(playlist);
    if (context.mounted) {
      AppFlushbar.success(
        context,
        wasPinned
            ? 'Unpinned "${playlist.title}"'
            : 'Pinned "${playlist.title}"',
      );
    }
  } catch (error) {
    if (context.mounted) {
      AppFlushbar.error(context, "Couldn't update pinned playlists: $error");
    }
  }
}
