import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:provider/provider.dart';

Future<void> toggleTrackLike(BuildContext context, Track track) async {
  try {
    await context.read<LibraryProvider>().toggleLike(track);
  } catch (error) {
    if (context.mounted) {
      AppFlushbar.error(context, "Couldn't update Liked Songs: $error");
    }
  }
}
