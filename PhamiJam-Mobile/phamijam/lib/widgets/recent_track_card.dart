import 'package:flutter/material.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:phamijam/widgets/scrim_icon_button.dart';

class RecentTrackCard extends StatefulWidget {
  final Track track;
  final bool isActive;
  final double width;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final bool isLiked;
  final VoidCallback? onToggleLike;
  final bool isDownloaded;
  final VoidCallback? onToggleDownload;
  final VoidCallback? onPlayNext;
  final VoidCallback? onAddToQueue;
  final VoidCallback? onEditSong;
  final VoidCallback? onShare;

  const RecentTrackCard({
    super.key,
    required this.track,
    required this.onTap,
    this.isActive = false,
    this.onMore,
    this.isLiked = false,
    this.onToggleLike,
    this.isDownloaded = false,
    this.onToggleDownload,
    this.onPlayNext,
    this.onAddToQueue,
    this.onEditSong,
    this.onShare,
    this.width = 140,
  });

  @override
  State<RecentTrackCard> createState() => _RecentTrackCardState();
}

class _RecentTrackCardState extends State<RecentTrackCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = widget.isActive
        ? colorScheme.primary
        : colorScheme.onSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onMore,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.width,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: widget.isActive
                ? colorScheme.primary.withValues(alpha: _hovering ? 0.16 : 0.12)
                : _hovering
                ? colorScheme.surfaceContainerHighest
                : colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: NetworkThumbnail(
                        url: widget.track.thumbnailUrl,
                        fit: BoxFit.cover,
                        iconSize: 32,
                      ),
                    ),
                  ),
                  if (widget.onToggleLike != null)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: ScrimIconButton(
                        icon: widget.isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        onTap: widget.onToggleLike!,
                        tooltip: widget.isLiked ? 'Unlike' : 'Like',
                      ),
                    ),
                  if (widget.onMore != null)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: const CircleBorder(),
                        child: PopupMenuButton<String>(
                          tooltip: 'More options',
                          padding: EdgeInsets.zero,
                          splashRadius: 16,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          onSelected: (value) {
                            switch (value) {
                              case 'play_next':
                                widget.onPlayNext?.call();
                              case 'add_to_queue':
                                widget.onAddToQueue?.call();
                              case 'add_to_playlist':
                                widget.onMore?.call();
                              case 'download':
                                widget.onToggleDownload?.call();
                              case 'edit_trim':
                                widget.onEditSong?.call();
                              case 'share':
                                widget.onShare?.call();
                            }
                          },
                          itemBuilder: (context) => [
                            if (widget.onPlayNext != null)
                              const PopupMenuItem(
                                value: 'play_next',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.playlist_play_rounded),
                                  title: Text('Play next'),
                                ),
                              ),
                            if (widget.onAddToQueue != null)
                              const PopupMenuItem(
                                value: 'add_to_queue',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.queue_music_rounded),
                                  title: Text('Add to queue'),
                                ),
                              ),
                            const PopupMenuItem(
                              value: 'add_to_playlist',
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.playlist_add_rounded),
                                title: Text('Add to playlist'),
                              ),
                            ),
                            if (widget.onToggleDownload != null)
                              PopupMenuItem(
                                value: 'download',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    widget.isDownloaded
                                        ? Icons.download_done_rounded
                                        : Icons.download_rounded,
                                  ),
                                  title: Text(
                                    widget.isDownloaded
                                        ? 'Remove download'
                                        : 'Download',
                                  ),
                                ),
                              ),
                            if (widget.onEditSong != null)
                              const PopupMenuItem(
                                value: 'edit_trim',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.content_cut_rounded),
                                  title: Text('Edit song'),
                                ),
                              ),
                            if (widget.onShare != null)
                              const PopupMenuItem(
                                value: 'share',
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(Icons.share_rounded),
                                  title: Text('Share'),
                                ),
                              ),
                          ],
                          child: const Padding(
                            padding: EdgeInsets.all(7),
                            child: Icon(
                              Icons.more_horiz_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (widget.onToggleDownload != null)
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: ScrimIconButton(
                        icon: widget.isDownloaded
                            ? Icons.download_done_rounded
                            : Icons.download_rounded,
                        onTap: widget.onToggleDownload!,
                        tooltip: widget.isDownloaded
                            ? 'Remove download'
                            : 'Download',
                      ),
                    ),
                  AnimatedOpacity(
                    opacity: _hovering || widget.isActive ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow.withValues(alpha: 0.45),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Icon(
                          widget.isActive
                              ? Icons.graphic_eq_rounded
                              : Icons.play_arrow_rounded,
                          color: colorScheme.onPrimary,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: activeColor),
              ),
              const SizedBox(height: 2),
              Text(
                widget.track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
