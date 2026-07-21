import 'package:flutter/material.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';

class TrackTile extends StatefulWidget {
  final Track track;
  final int? index;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final VoidCallback? onArtistTap;

  final VoidCallback? onPlayNext;

  final Future<bool> Function()? onRemove;

  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.index,
    this.isActive = false,
    this.onMore,
    this.onArtistTap,
    this.onPlayNext,
    this.onRemove,
  });

  @override
  State<TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends State<TrackTile> {
  bool _hovering = false;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString();
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = widget.isActive
        ? colorScheme.primary
        : colorScheme.onSurface;
    final tile = MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: widget.isActive
                ? colorScheme.primary.withValues(alpha: _hovering ? 0.16 : 0.12)
                : _hovering
                ? colorScheme.surfaceContainerHigh
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: widget.isActive
                    ? Icon(
                        Icons.graphic_eq_rounded,
                        color: colorScheme.primary,
                        size: 18,
                      )
                    : widget.index != null
                    ? (_hovering
                          ? Icon(
                              Icons.play_arrow_rounded,
                              color: colorScheme.primary,
                              size: 18,
                            )
                          : Text(
                              '${widget.index}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ))
                    : Icon(
                        Icons.music_note_rounded,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.6,
                        ),
                        size: 18,
                      ),
              ),
              const SizedBox(width: 8),
              NetworkThumbnail(
                url: widget.track.thumbnailUrl,
                width: 40,
                height: 40,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: activeColor),
                    ),
                    widget.onArtistTap == null
                        ? Text(
                            widget.track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          )
                        : GestureDetector(
                            onTap: widget.onArtistTap,
                            child: Text(
                              widget.track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    decoration: TextDecoration.underline,
                                  ),
                            ),
                          ),
                  ],
                ),
              ),
              Text(
                _formatDuration(widget.track.duration),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (widget.onMore != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: widget.onMore,
                  icon: Icon(
                    Icons.more_horiz_rounded,
                    color: colorScheme.onSurfaceVariant,
                    size: 18,
                  ),
                  splashRadius: 18,
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (widget.onPlayNext == null && widget.onRemove == null) return tile;

    final DismissDirection direction;
    if (widget.onPlayNext != null && widget.onRemove != null) {
      direction = DismissDirection.horizontal;
    } else if (widget.onPlayNext != null) {
      direction = DismissDirection.startToEnd;
    } else {
      direction = DismissDirection.endToStart;
    }

    return Dismissible(
      key: ValueKey('track-tile-${widget.track.id}'),
      direction: direction,
      dismissThresholds: {
        if (widget.onPlayNext != null) DismissDirection.startToEnd: 0.3,
        if (widget.onRemove != null) DismissDirection.endToStart: 0.4,
      },
      confirmDismiss: (dismissDirection) async {
        if (dismissDirection == DismissDirection.startToEnd) {
          widget.onPlayNext?.call();
          return false;
        }
        if (dismissDirection == DismissDirection.endToStart) {
          return await widget.onRemove?.call() ?? false;
        }
        return false;
      },
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.playlist_play_rounded, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Add to play next',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: colorScheme.error.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Remove',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.delete_rounded, color: colorScheme.error),
          ],
        ),
      ),
      child: tile,
    );
  }
}
