import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:provider/provider.dart';

IconData volumeIcon(double volume) {
  if (volume <= 0) return Icons.volume_off_rounded;
  if (volume < 0.5) return Icons.volume_down_rounded;
  return Icons.volume_up_rounded;
}

Future<void> showVolumeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _VolumeSheet(),
  );
}

class _VolumeSheet extends StatefulWidget {
  const _VolumeSheet();

  @override
  State<_VolumeSheet> createState() => _VolumeSheetState();
}

class _VolumeSheetState extends State<_VolumeSheet> {
  double? _preMuteVolume;
  bool _editing = false;
  late final TextEditingController _textController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleMute(PlayerProvider player) {
    if (player.volume > 0) {
      _preMuteVolume = player.volume;
      player.setVolume(0);
    } else {
      player.setVolume(
        (_preMuteVolume != null && _preMuteVolume! > 0) ? _preMuteVolume! : 0.8,
      );
    }
  }

  void _startEditing(double currentVolume) {
    _textController.text = (currentVolume * 100).round().toString();
    setState(() => _editing = true);
    _focusNode.requestFocus();
  }

  void _commitEdit(PlayerProvider player) {
    final parsed = int.tryParse(_textController.text.trim());
    if (parsed != null) {
      final clamped = parsed.clamp(0, 100);
      player.setVolume(clamped / 100);
      if (clamped > 0) _preMuteVolume = clamped / 100;
    }
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Consumer<PlayerProvider>(
      builder: (context, player, _) {
        final percent = (player.volume * 100).round();
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
                Text('Volume', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 20),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _toggleMute(player),
                      icon: Icon(
                        volumeIcon(player.volume),
                        color: colorScheme.primary,
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: colorScheme.primary,
                          inactiveTrackColor:
                              colorScheme.surfaceContainerHighest,
                          thumbColor: colorScheme.primary,
                          overlayColor: colorScheme.primary.withValues(
                            alpha: 0.15,
                          ),
                        ),
                        child: Slider(
                          value: player.volume.clamp(0.0, 1.0),
                          onChanged: (value) {
                            player.setVolume(value);
                            if (value > 0) _preMuteVolume = value;
                          },
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _editing
                          ? null
                          : () => _startEditing(player.volume),
                      child: SizedBox(
                        width: 56,
                        child: _editing
                            ? TextField(
                                controller: _textController,
                                focusNode: _focusNode,
                                autofocus: true,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(3),
                                ],
                                style: TextStyle(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  suffixText: '%',
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onSubmitted: (_) => _commitEdit(player),
                                onTapOutside: (_) => _commitEdit(player),
                              )
                            : Text(
                                '$percent%',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap the number to type an exact level.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
