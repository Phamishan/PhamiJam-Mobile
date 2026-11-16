import 'dart:async';
import 'package:flutter/material.dart';
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
  bool _failed = false;
  String? _failedForTrackId;

  static const _candidateTimeout = Duration(seconds: 12);
  static const _driftCheckInterval = Duration(seconds: 2);
  static const _driftTolerance = Duration(milliseconds: 350);

  static const Map<String, String> _youtubeHttpHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Mobile Safari/537.36',
    'Referer': 'https://www.youtube.com/',
  };

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
    if (track.id == _failedForTrackId) return;
    if (_loading) return;
    _loading = true;
    if (_failed) {
      _failed = false;
      if (mounted) setState(() {});
    }

    try {
      final urls = await widget.player.videoOnlyUrlsForCurrentTrack();
      if (!mounted || widget.player.currentTrack?.id != track.id) return;

      await _teardown();
      VideoPlayerController? ready;
      for (final url in urls) {
        final controller = VideoPlayerController.networkUrl(
          url,
          httpHeaders: _youtubeHttpHeaders,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
        try {
          await controller.initialize().timeout(_candidateTimeout);
          ready = controller;
          break;
        } catch (error) {
          debugPrint('VideoSurface: candidate failed for ${track.id}: $error');
          await controller.dispose();
          if (!mounted || widget.player.currentTrack?.id != track.id) return;
        }
      }

      if (ready == null) {
        _markFailed(track.id);
        return;
      }
      if (!mounted || widget.player.currentTrack?.id != track.id) {
        await ready.dispose();
        return;
      }
      _controller = ready;
      await ready.setVolume(0);
      await ready.seekTo(widget.player.position);
      if (widget.player.isPlaying) {
        await ready.play();
      }
      _loadedForTrackId = track.id;
      _driftTimer = Timer.periodic(_driftCheckInterval, (_) => _correctDrift());
      if (mounted) setState(() {});
    } catch (error, stackTrace) {
      debugPrint('VideoSurface: failed to load video for ${track.id}: $error');
      debugPrintStack(stackTrace: stackTrace);
      await _teardown();
      _markFailed(track.id);
    } finally {
      _loading = false;
    }
  }

  void _markFailed(String trackId) {
    _failedForTrackId = trackId;
    _failed = true;
    if (mounted) setState(() {});
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
      final colorScheme = Theme.of(context).colorScheme;
      return ColoredBox(
        color: colorScheme.surfaceContainerHigh,
        child: Center(
          child: _failed
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Video isn\'t available for this song',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                )
              : const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
        ),
      );
    }
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
