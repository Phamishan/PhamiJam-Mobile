import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/widgets/scrim_icon_button.dart';
import 'package:phamijam/widgets/video_surface.dart';
import 'package:provider/provider.dart';

class FullscreenVideoPage extends StatefulWidget {
  const FullscreenVideoPage({super.key});

  @override
  State<FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<FullscreenVideoPage> {
  PlayerProvider? _player;

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _player = context.read<PlayerProvider>();
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (player.currentTrack != null)
              Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: VideoSurface(player: player),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: ScrimIconButton(
                icon: Icons.fullscreen_exit_rounded,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
