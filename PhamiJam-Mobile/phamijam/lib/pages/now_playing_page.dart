import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';
import 'package:phamijam/pages/artist_page.dart';
import 'package:phamijam/pages/fullscreen_video_page.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:phamijam/widgets/pull_down_to_dismiss.dart';
import 'package:phamijam/widgets/scrim_icon_button.dart';
import 'package:phamijam/widgets/swipe_back.dart';
import 'package:phamijam/widgets/video_surface.dart';
import 'package:phamijam/widgets/volume_control.dart';
import 'package:provider/provider.dart';

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  PlayerProvider? _player;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _player = context.read<PlayerProvider>();
  }

  @override
  void dispose() {
    _player?.setVideoSurfaceHost(VideoSurfaceHost.none);
    super.dispose();
  }

  void _toggleVideoMode(PlayerProvider player) {
    player.setVideoSurfaceHost(
      player.videoSurfaceHost == VideoSurfaceHost.nowPlaying
          ? VideoSurfaceHost.none
          : VideoSurfaceHost.nowPlaying,
    );
  }

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const FullscreenVideoPage(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final track = player.currentTrack;
        final colorScheme = Theme.of(context).colorScheme;
        final showingVideo =
            player.videoSurfaceHost == VideoSurfaceHost.nowPlaying;

        return PullDownToDismiss(
          child: SwipeBack(
            child: Scaffold(
              backgroundColor: colorScheme.surface,
              body: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary.withValues(alpha: 0.35),
                      colorScheme.surface,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    child: track == null
                        ? Center(
                            child: Text(
                              'Nothing playing',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          )
                        : Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    icon: Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 30,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    'Now Playing',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                  IconButton(
                                    onPressed: () => showVolumeSheet(context),
                                    icon: Icon(
                                      volumeIcon(player.volume),
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                                child: AspectRatio(
                                  aspectRatio: showingVideo ? 16 / 9 : 1,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (showingVideo)
                                          VideoSurface(player: player)
                                        else
                                          NetworkThumbnail(
                                            url: track.thumbnailUrl,
                                            fit: BoxFit.cover,
                                            iconSize: 40,
                                          ),
                                        Positioned(
                                          right: 8,
                                          bottom: 8,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (showingVideo)
                                                ScrimIconButton(
                                                  icon:
                                                      Icons.fullscreen_rounded,
                                                  onTap: () =>
                                                      _openFullscreen(context),
                                                ),
                                              if (showingVideo)
                                                const SizedBox(width: 8),
                                              ScrimIconButton(
                                                icon: showingVideo
                                                    ? Icons.image_rounded
                                                    : Icons
                                                          .smart_display_rounded,
                                                onTap: () =>
                                                    _toggleVideoMode(player),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              SizedBox(
                                height: 30,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final style = Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(fontSize: 22);
                                    final width = _textWidth(
                                      track.title,
                                      style,
                                    );
                                    if (width <= constraints.maxWidth) {
                                      return Text(
                                        track.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: style,
                                      );
                                    }
                                    return Marquee(
                                      text: track.title,
                                      style: style,
                                      blankSpace: 50,
                                      velocity: 28,
                                      pauseAfterRound: const Duration(
                                        seconds: 2,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 6),
                              Builder(
                                builder: (context) {
                                  final onArtistTap = openArtistPageCallback(
                                    context,
                                    channelId: track.channelId,
                                    artistName: track.artist,
                                  );
                                  final artistText = Text(
                                    track.artist,
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(
                                          decoration: onArtistTap == null
                                              ? null
                                              : TextDecoration.underline,
                                        ),
                                  );
                                  return onArtistTap == null
                                      ? artistText
                                      : GestureDetector(
                                          onTap: onArtistTap,
                                          child: artistText,
                                        );
                                },
                              ),
                              const SizedBox(height: 24),
                              ProgressBar(
                                progress: player.position,
                                total: track.duration,
                                barHeight: 4,
                                thumbRadius: 6,
                                timeLabelLocation: TimeLabelLocation.below,
                                timeLabelTextStyle: Theme.of(
                                  context,
                                ).textTheme.bodySmall,
                                progressBarColor: colorScheme.primary,
                                baseBarColor:
                                    colorScheme.surfaceContainerHighest,
                                thumbColor: colorScheme.primary,
                                onSeek: player.seek,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  IconButton(
                                    onPressed: player.toggleShuffle,
                                    icon: Icon(
                                      Icons.shuffle_rounded,
                                      color: player.shuffle
                                          ? colorScheme.primary
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: player.previous,
                                    iconSize: 34,
                                    icon: Icon(
                                      Icons.skip_previous_rounded,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: player.togglePlayPause,
                                    child: Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: colorScheme.primary,
                                      ),
                                      child: Icon(
                                        player.isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color: colorScheme.onPrimary,
                                        size: 34,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: player.next,
                                    iconSize: 34,
                                    icon: Icon(
                                      Icons.skip_next_rounded,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: player.cycleRepeatMode,
                                    icon: Icon(
                                      player.repeatMode == PlayerRepeatMode.one
                                          ? Icons.repeat_one_rounded
                                          : Icons.repeat_rounded,
                                      color:
                                          player.repeatMode ==
                                              PlayerRepeatMode.off
                                          ? colorScheme.onSurfaceVariant
                                          : colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _textWidth(String text, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }
}
