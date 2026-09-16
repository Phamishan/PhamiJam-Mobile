import 'package:flutter/material.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:provider/provider.dart';

class RemoteSessionBanner extends StatelessWidget {
  const RemoteSessionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final shouldShow = context.select<PlayerProvider, bool>(
      (p) => p.shouldShowRemoteBanner,
    );
    if (!shouldShow) return const SizedBox.shrink();

    final deviceName = context.select<PlayerProvider, String?>(
      (p) => p.remoteSession?.deviceName,
    );
    final trackTitle = context.select<PlayerProvider, String?>(
      (p) => p.remoteSession?.currentTrack?.title,
    );
    if (deviceName == null) return const SizedBox.shrink();
    final player = context.read<PlayerProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.headphones_rounded, color: colorScheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Playing on $deviceName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  trackTitle ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: player.resumeRemoteSessionLocally,
            child: const Text('Resume'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: player.enterRemoteControl,
            child: const Text('Control'),
          ),
          IconButton(
            onPressed: player.dismissRemoteBanner,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
            splashRadius: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}
