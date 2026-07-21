import 'package:flutter/material.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';

class PlaylistCard extends StatefulWidget {
  final Playlist playlist;
  final double width;
  final VoidCallback onTap;
  final VoidCallback? onPlay;

  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.onTap,
    this.onPlay,
    this.width = 148,
  });

  @override
  State<PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<PlaylistCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.width,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _hovering ? colorScheme.surfaceContainerHighest : colorScheme.surfaceContainer,
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
                        url: widget.playlist.thumbnailUrl,
                        fit: BoxFit.cover,
                        iconSize: 36,
                      ),
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: _hovering ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: GestureDetector(
                        onTap: widget.onPlay,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: colorScheme.shadow.withValues(alpha: 0.45), blurRadius: 8)],
                          ),
                          child: Icon(Icons.play_arrow_rounded, color: colorScheme.onPrimary, size: 24),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.playlist.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                widget.playlist.subtitle,
                maxLines: 2,
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
