import 'package:flutter/material.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/pages/artist_page.dart';
import 'package:phamijam/pages/now_playing_page.dart';
import 'package:phamijam/pages/queue_page.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:phamijam/widgets/remote_control_badge.dart';
import 'package:provider/provider.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final swipeToDismiss = context
        .watch<SettingsProvider>()
        .miniPlayerSwipeToDismiss;
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final track = player.currentTrack;
        if (track == null) return const SizedBox.shrink();

        final progress = track.duration.inMilliseconds == 0
            ? 0.0
            : player.position.inMilliseconds / track.duration.inMilliseconds;

        return Dismissible(
          key: ValueKey('mini-player-${track.id}'),
          direction: swipeToDismiss
              ? DismissDirection.horizontal
              : DismissDirection.none,
          onDismissed: (_) => player.dismissPlayback(),
          background: _DismissBackground(alignment: Alignment.centerLeft),
          secondaryBackground: _DismissBackground(
            alignment: Alignment.centerRight,
          ),
          child: GestureDetector(
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const NowPlayingPage())),
            child: Container(
              height: 62,
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation(colorScheme.primary),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      children: [
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 42,
                          height: 42,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              NetworkThumbnail(
                                url: track.thumbnailUrl,
                                width: 42,
                                height: 42,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              if (player.isRemoteControlling)
                                Positioned(
                                  right: -4,
                                  bottom: -4,
                                  child: RemoteControlBadge(
                                    deviceName:
                                        player.remoteSession?.deviceName ??
                                        'device',
                                    size: 18,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              _buildArtistText(context, track),
                            ],
                          ),
                        ),
                        _MiniPlayerIconButton(
                          icon: Icons.skip_previous_rounded,
                          onPressed: player.previous,
                          color: colorScheme.onSurface,
                        ),
                        if (player.isLoadingTrack)
                          const SizedBox(
                            width: 34,
                            height: 34,
                            child: Padding(
                              padding: EdgeInsets.all(9),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            ),
                          )
                        else
                          _MiniPlayerIconButton(
                            icon: player.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            onPressed: player.togglePlayPause,
                            color: colorScheme.onSurface,
                            size: 26,
                          ),
                        _MiniPlayerIconButton(
                          icon: Icons.skip_next_rounded,
                          onPressed: player.next,
                          color: colorScheme.onSurface,
                        ),
                        _MiniPlayerIconButton(
                          icon: Icons.queue_music_rounded,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const QueuePage(),
                            ),
                          ),
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DismissBackground extends StatelessWidget {
  final Alignment alignment;

  const _DismissBackground({required this.alignment});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: alignment,
      decoration: BoxDecoration(
        color: colorScheme.error.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.close_rounded, color: colorScheme.error, size: 28),
    );
  }
}

class _MiniPlayerIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final double size;

  const _MiniPlayerIconButton({
    required this.icon,
    required this.onPressed,
    required this.color,
    this.size = 22,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      splashRadius: 18,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      icon: Icon(icon, color: color, size: size),
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
