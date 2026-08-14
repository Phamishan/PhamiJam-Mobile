import 'dart:async';

import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/widgets/scrim_icon_button.dart';
import 'package:phamijam/widgets/video_surface.dart';
import 'package:phamijam/widgets/volume_control.dart';
import 'package:provider/provider.dart';

class FullscreenVideoPage extends StatefulWidget {
  const FullscreenVideoPage({super.key});

  @override
  State<FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<FullscreenVideoPage> {
  PlayerProvider? _player;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  static const _autoHideDelay = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    context.read<PlayerProvider>().setVideoSurfaceHost(
      VideoSurfaceHost.fullscreen,
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scheduleAutoHide();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _player = context.read<PlayerProvider>();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.bottom],
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _player?.setVideoSurfaceHost(VideoSurfaceHost.nowPlaying);
    super.dispose();
  }

  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_autoHideDelay, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _scheduleAutoHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _keepAlive() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _scheduleAutoHide();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          child: Stack(
            children: [
              if (track != null)
                Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: VideoSurface(player: player),
                  ),
                ),
              IgnorePointer(
                ignoring: !_controlsVisible,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.55),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.65),
                        ],
                        stops: const [0, 0.2, 0.7, 1],
                      ),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              ScrimIconButton(
                                icon: Icons.fullscreen_exit_rounded,
                                onTap: () => Navigator.of(context).maybePop(),
                              ),
                              const SizedBox(width: 12),
                              if (track != null)
                                Expanded(
                                  child: Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 12),
                              ScrimIconButton(
                                icon: volumeIcon(player.volume),
                                onTap: () {
                                  _keepAlive();
                                  showVolumeSheet(context);
                                },
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (track != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            child: ProgressBar(
                              progress: player.position,
                              total: player.duration,
                              barHeight: 3,
                              thumbRadius: 6,
                              timeLabelLocation: TimeLabelLocation.sides,
                              timeLabelTextStyle: const TextStyle(
                                color: Colors.white,
                              ),
                              progressBarColor: Colors.white,
                              baseBarColor: Colors.white.withValues(
                                alpha: 0.3,
                              ),
                              bufferedBarColor: Colors.white.withValues(
                                alpha: 0.45,
                              ),
                              thumbColor: Colors.white,
                              onSeek: (position) {
                                _keepAlive();
                                player.seek(position);
                              },
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                onPressed: () {
                                  _keepAlive();
                                  player.toggleShuffle();
                                },
                                icon: Icon(
                                  Icons.shuffle_rounded,
                                  color: player.shuffle
                                      ? Colors.white
                                      : Colors.white54,
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  _keepAlive();
                                  player.previous();
                                },
                                iconSize: 34,
                                icon: const Icon(
                                  Icons.skip_previous_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () {
                                  _keepAlive();
                                  player.togglePlayPause();
                                },
                                child: Container(
                                  width: 56,
                                  height: 56,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                  ),
                                  child: player.isLoadingTrack
                                      ? const Padding(
                                          padding: EdgeInsets.all(16),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.6,
                                            color: Colors.black,
                                          ),
                                        )
                                      : Icon(
                                          player.isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          color: Colors.black,
                                          size: 30,
                                        ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () {
                                  _keepAlive();
                                  player.next();
                                },
                                iconSize: 34,
                                icon: const Icon(
                                  Icons.skip_next_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  _keepAlive();
                                  player.cycleRepeatMode();
                                },
                                icon: Icon(
                                  player.repeatMode == PlayerRepeatMode.one
                                      ? Icons.repeat_one_rounded
                                      : Icons.repeat_rounded,
                                  color: player.repeatMode ==
                                          PlayerRepeatMode.off
                                      ? Colors.white54
                                      : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
