import 'package:flutter/material.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:phamijam/widgets/swipe_back.dart';
import 'package:phamijam/widgets/track_tile.dart';
import 'package:provider/provider.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  Future<void> _confirmClearAll(
    BuildContext context,
    DownloadsProvider downloads,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear all downloads?'),
        content: const Text(
          'This deletes every downloaded song from this device. '
          "This can't be undone.",
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
      await downloads.clearAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final downloads = context.watch<DownloadsProvider>();
    final tracks = downloads.all;

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
                      'Downloaded Songs',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4),
                  child: Text(
                    '${downloads.totalTracks} songs · '
                    '${formatDownloadSize(downloads.totalSizeBytes)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: tracks.isEmpty
                      ? Center(
                          child: Text(
                            'No downloaded songs yet.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 16),
                          children: [
                            for (var i = 0; i < tracks.length; i++)
                              TrackTile(
                                track: tracks[i].track,
                                onTap: () => context
                                    .read<PlayerProvider>()
                                    .playQueue(
                                      [for (final d in tracks) d.track],
                                      startIndex: i,
                                    ),
                                isDownloaded: true,
                                onToggleDownload: () =>
                                    downloads.remove(tracks[i].track.videoId!),
                              ),
                          ],
                        ),
                ),
                if (tracks.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 16, bottom: 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmClearAll(context, downloads),
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: colorScheme.error,
                        ),
                        label: const Text('Clear all downloads'),
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
