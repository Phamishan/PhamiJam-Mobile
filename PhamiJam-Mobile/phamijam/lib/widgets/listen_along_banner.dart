import 'package:flutter/material.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:provider/provider.dart';

class ListenAlongBanner extends StatelessWidget {
  const ListenAlongBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final isListeningAlong = context.select<PlayerProvider, bool>(
      (p) => p.isListeningAlong,
    );
    if (!isListeningAlong) return const SizedBox.shrink();

    final friendName = context.select<PlayerProvider, String?>(
      (p) => p.listenAlongFriendName,
    );
    final player = context.read<PlayerProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.sync_alt_rounded,
            color: colorScheme.onPrimaryContainer,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Listening along with ${friendName ?? 'a friend'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.onPrimaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: player.stopListenAlong,
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}
