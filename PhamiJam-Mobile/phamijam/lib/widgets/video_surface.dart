import 'package:flutter/widgets.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart'
    hide ProgressBar;

final GlobalKey _videoSurfaceKey = GlobalKey();

class VideoSurface extends StatelessWidget {
  const VideoSurface({
    super.key,
    required this.player,
    this.showVideoProgressIndicator = false,
  });

  final PlayerProvider player;
  final bool showVideoProgressIndicator;

  @override
  Widget build(BuildContext context) {
    final controller = player.youtubeController;
    if (controller == null) return const SizedBox.shrink();

    return KeyedSubtree(
      key: _videoSurfaceKey,
      child: YoutubePlayer(
        controller: controller,
        showVideoProgressIndicator: showVideoProgressIndicator,
        onReady: player.resyncVideoSurface,
      ),
    );
  }
}
