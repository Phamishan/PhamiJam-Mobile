import 'package:flutter/material.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:provider/provider.dart';

const List<int> _sleepTimerPresetMinutes = [5, 10, 15, 30, 45, 60];

Future<void> showSleepTimerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _SleepTimerSheet(),
  );
}

class _SleepTimerSheet extends StatelessWidget {
  const _SleepTimerSheet();

  String _remainingLabel(DateTime endsAt) {
    final remaining = endsAt.difference(DateTime.now());
    if (remaining.isNegative) return 'Ending soon';
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')} remaining';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final endsAt = player.sleepTimerEndsAt;
        final endOfTrack = player.isSleepTimerEndOfTrackScheduled;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sleep timer',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (endsAt != null || endOfTrack) ...[
                  const SizedBox(height: 4),
                  Text(
                    endOfTrack
                        ? 'Stopping at the end of this track'
                        : _remainingLabel(endsAt!),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final minutes in _sleepTimerPresetMinutes)
                      ChoiceChip(
                        label: Text('$minutes min'),
                        selected: false,
                        onSelected: (_) {
                          player.setSleepTimer(Duration(minutes: minutes));
                          Navigator.of(context).pop();
                        },
                      ),
                    ChoiceChip(
                      label: const Text('End of track'),
                      selected: endOfTrack,
                      onSelected: (_) {
                        player.setSleepTimerEndOfTrack();
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
                if (endsAt != null || endOfTrack) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      player.cancelSleepTimer();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Turn off'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
