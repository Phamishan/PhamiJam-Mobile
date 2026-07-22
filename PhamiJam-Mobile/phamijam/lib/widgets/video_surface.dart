import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:video_player/video_player.dart';

class VideoSurface extends StatefulWidget {
  const VideoSurface({super.key, required this.player});
  final PlayerProvider player;

  @override
  State<VideoSurface> createState() => _VideoSurfaceState();
}

class _VideoSurfaceState extends State<VideoSurface> {
  VideoPlayerController? _controller;
  Timer? _driftTimer;
  String? _loadedForTrackId;
  bool _loading = false;

  static const _driftCheckInterval = Duration(seconds: 2);
  static const _driftTolerance = Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    widget.player.addListener(_handlePlayerChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant VideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      oldWidget.player.removeListener(_handlePlayerChanged);
      widget.player.addListener(_handlePlayerChanged);
    }
    _load();
  }

  void _handlePlayerChanged() {
    final trackId = widget.player.currentTrack?.id;
    if (trackId != _loadedForTrackId) {
      _load();
    } else {
      _syncPlayPause();
    }
  }

  Future<void> _load() async {
    final track = widget.player.currentTrack;
    if (track == null) {
      await _teardown();
      return;
    }
    if (track.id == _loadedForTrackId && _controller != null) return;
    if (_loading) return;
    _loading = true;

    try {
      final url = await widget.player.videoOnlyUrlForCurrentTrack();
      if (!mounted || widget.player.currentTrack?.id != track.id) return;
      if (url == null) {
        await _teardown();
        return;
      }

      await _teardown();
      final controller = VideoPlayerController.networkUrl(
        url,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _controller = controller;
      _loadedForTrackId = track.id;
      await controller.initialize();
      await controller.setVolume(0);
      await controller.seekTo(widget.player.position);
      if (widget.player.isPlaying) {
        await controller.play();
      }
      _driftTimer = Timer.periodic(_driftCheckInterval, (_) => _correctDrift());
      if (mounted) setState(() {});
    } finally {
      _loading = false;
    }
  }

  Future<void> _correctDrift() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final authoritative = widget.player.position;
    final actual = controller.value.position;
    if ((authoritative - actual).abs() > _driftTolerance) {
      await controller.seekTo(authoritative);
    }
  }

  Future<void> _syncPlayPause() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.player.isPlaying && !controller.value.isPlaying) {
      await controller.seekTo(widget.player.position);
      await controller.play();
    } else if (!widget.player.isPlaying && controller.value.isPlaying) {
      await controller.pause();
    }
  }

  Future<void> _teardown() async {
    _driftTimer?.cancel();
    _driftTimer = null;
    final controller = _controller;
    _controller = null;
    _loadedForTrackId = null;
    if (controller != null) {
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    widget.player.removeListener(_handlePlayerChanged);
    _teardown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    // YouTube's video-only streams are often encoded with a few extra
    // padding pixels along the right edge (codec block-alignment), which
    // shows up as a thin line of garbage-colored pixels once BoxFit.cover
    // stretches the raw texture. Scale up, anchored at the left edge so all
    // the added width crops off the right (where the artifact is), and clip.
    return ClipRect(
      child: Transform.scale(
        scale: 1.06,
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}
