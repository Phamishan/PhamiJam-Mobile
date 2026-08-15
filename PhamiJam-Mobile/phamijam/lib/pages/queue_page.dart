import 'package:flutter/material.dart';
import 'package:phamijam/components/add_to_playlist_sheet.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/components/download_action.dart';
import 'package:phamijam/components/like_action.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/pages/artist_page.dart';
import 'package:phamijam/pages/now_playing_page.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:phamijam/widgets/swipe_back.dart';
import 'package:phamijam/widgets/track_tile.dart';
import 'package:provider/provider.dart';

class QueuePage extends StatelessWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final library = context.watch<LibraryProvider>();
    final downloads = context.watch<DownloadsProvider>();

    return SwipeBack(
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Consumer<PlayerProvider>(
            builder: (context, player, _) {
              final queue = player.queue;
              final currentIndex = player.queueIndex;
              final upNext = currentIndex >= 0 && currentIndex < queue.length
                  ? queue.sublist(currentIndex + 1)
                  : <Track>[];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: Icon(
                            Icons.arrow_back_rounded,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Queue',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ),
                        if (upNext.isNotEmpty)
                          TextButton.icon(
                            onPressed: () {
                              player.clearQueue();
                              AppFlushbar.success(context, 'Queue cleared');
                            },
                            icon: const Icon(
                              Icons.playlist_remove_rounded,
                              size: 18,
                            ),
                            label: const Text('Clear'),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: queue.isEmpty
                        ? Center(
                            child: Text(
                              'Nothing queued',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            children: [
                              if (player.currentTrack != null) ...[
                                Text(
                                  'NOW PLAYING',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(letterSpacing: 1.2),
                                ),
                                const SizedBox(height: 8),
                                _NowPlayingTile(track: player.currentTrack!),
                                const SizedBox(height: 20),
                              ],
                              Text(
                                'NEXT UP',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(letterSpacing: 1.2),
                              ),
                              const SizedBox(height: 8),
                              if (upNext.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  child: Text(
                                    'No more tracks queued.',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                )
                              else
                                ReorderableListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  buildDefaultDragHandles: false,
                                  itemCount: upNext.length,
                                  onReorderItem: (oldIndex, newIndex) {
                                    player.reorderQueue(
                                      currentIndex + 1 + oldIndex,
                                      currentIndex + 1 + newIndex,
                                    );
                                  },
                                  itemBuilder: (context, i) {
                                    final queueIndex = currentIndex + 1 + i;
                                    final track = queue[queueIndex];
                                    return Row(
                                      key: ValueKey('queue-item-$queueIndex'),
                                      children: [
                                        Expanded(
                                          child: TrackTile(
                                            index: i + 1,
                                            track: track,
                                            onTap: () =>
                                                player.playFromQueue(
                                                  queueIndex,
                                                ),
                                            onPlayNext: () =>
                                                player.playNext(track),
                                            onRemove: () async {
                                              player.removeFromQueue(
                                                queueIndex,
                                              );
                                              if (context.mounted) {
                                                AppFlushbar.success(
                                                  context,
                                                  'Removed from queue',
                                                );
                                              }
                                              return true;
                                            },
                                            onMore: () => showAddToPlaylistSheet(
                                              context,
                                              track,
                                            ),
                                            isLiked: library.isLiked(track),
                                            onToggleLike: () =>
                                                toggleTrackLike(context, track),
                                            isDownloaded: downloads.isDownloaded(
                                              track.videoId,
                                            ),
                                            downloadProgress: downloads
                                                .progressFor(track.videoId),
                                            onToggleDownload: () =>
                                                toggleTrackDownload(
                                                  context,
                                                  track,
                                                ),
                                            onCancelDownload:
                                                track.videoId == null
                                                ? null
                                                : () => downloads
                                                      .cancelDownload(
                                                        track.videoId!,
                                                      ),
                                            onArtistTap:
                                                openArtistPageCallback(
                                                  context,
                                                  channelId: track.channelId,
                                                  artistName: track.artist,
                                                ),
                                          ),
                                        ),
                                        ReorderableDragStartListener(
                                          index: i,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            child: Icon(
                                              Icons.drag_handle_rounded,
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NowPlayingTile extends StatelessWidget {
  final Track track;

  const _NowPlayingTile({required this.track});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const NowPlayingPage())),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              NetworkThumbnail(
                url: track.thumbnailUrl,
                width: 48,
                height: 48,
                borderRadius: BorderRadius.circular(6),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colorScheme.primary,
                      ),
                    ),
                    _buildArtistText(context, track),
                  ],
                ),
              ),
              Icon(
                Icons.graphic_eq_rounded,
                color: colorScheme.primary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _buildArtistText(BuildContext context, Track track) {
  final onArtistTap = openArtistPageCallback(
    context,
    channelId: track.channelId,
    artistName: track.artist,
  );
  final artistText = Text(
    track.artist,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      decoration: onArtistTap == null ? null : TextDecoration.underline,
    ),
  );
  return onArtistTap == null
      ? artistText
      : GestureDetector(onTap: onArtistTap, child: artistText);
}
