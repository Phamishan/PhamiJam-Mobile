import 'package:flutter/material.dart';

class PlayButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool isPlaying;
  const PlayButton({super.key, required this.onTap, this.isPlaying = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: onTap == null
          ? colorScheme.surfaceContainerHighest
          : colorScheme.primary,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Icon(
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: onTap == null
                ? colorScheme.onSurfaceVariant.withValues(alpha: 0.6)
                : colorScheme.onPrimary,
            size: 34,
          ),
        ),
      ),
    );
  }
}
