import 'package:flutter/material.dart';
import 'package:phamijam/components/like_action.dart';
import 'package:phamijam/models/edited_song_trim.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/providers/edited_songs_provider.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:phamijam/widgets/swipe_back.dart';
import 'package:provider/provider.dart';

class EditedSongsPage extends StatelessWidget {
  const EditedSongsPage({super.key});

  String _formatMs(int ms) {
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmClearAll(
    BuildContext context,
    EditedSongsProvider editedSongs,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear all edited songs?'),
        content: const Text(
          'This resets every trimmed song back to playing in full.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      for (final trim in List.of(editedSongs.all)) {
        await editedSongs.removeTrim(trim.videoId);
      }
    }
  }

  Widget _buildRow(
    BuildContext context,
    ColorScheme colorScheme,
    EditedSongsProvider editedSongs,
    LibraryProvider library,
    EditedSongTrim trim,
  ) {
    final track = Track(
      id: trim.videoId,
      title: trim.title,
      artist: trim.artist,
      thumbnailUrl: trim.thumbnailUrl,
      videoId: trim.videoId,
    );
    return ListTile(
      leading: NetworkThumbnail(
        url: trim.thumbnailUrl,
        width: 44,
        height: 44,
        borderRadius: BorderRadius.circular(4),
      ),
      title: Text(
        trim.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_formatMs(trim.startMs)} - ${_formatMs(trim.endMs)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => toggleTrackLike(context, track),
            icon: Icon(
              library.isLiked(track)
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          IconButton(
            tooltip: 'Reset',
            onPressed: () => editedSongs.removeTrim(trim.videoId),
            icon: Icon(
              Icons.restart_alt_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      onTap: () => context.read<PlayerProvider>().playQueue([track]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final editedSongs = context.watch<EditedSongsProvider>();
    final library = context.watch<LibraryProvider>();
    final trims = List.of(editedSongs.all)
      ..sort((a, b) => a.title.compareTo(b.title));

    return SwipeBack(
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Edited Songs',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4),
                  child: Text(
                    '${trims.length} songs trimmed',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: trims.isEmpty
                      ? Center(
                          child: Text(
                            'No edited songs yet.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 16),
                          children: [
                            for (final trim in trims)
                              _buildRow(
                                context,
                                colorScheme,
                                editedSongs,
                                library,
                                trim,
                              ),
                          ],
                        ),
                ),
                if (trims.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 16, bottom: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _confirmClearAll(context, editedSongs),
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: colorScheme.error,
                        ),
                        label: const Text('Clear all edited songs'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.error,
                          side: BorderSide(color: colorScheme.error),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
