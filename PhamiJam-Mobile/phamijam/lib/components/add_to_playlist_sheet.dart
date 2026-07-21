import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:provider/provider.dart';

Future<void> showAddToPlaylistSheet(BuildContext context, Track track) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _AddToPlaylistSheet(track: track),
  );
}

class _AddToPlaylistSheet extends StatefulWidget {
  final Track track;

  const _AddToPlaylistSheet({required this.track});

  @override
  State<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<_AddToPlaylistSheet> {
  final Set<String> _selectedIds = {};
  bool _submitting = false;

  void _toggle(String playlistId) {
    setState(() {
      if (!_selectedIds.remove(playlistId)) _selectedIds.add(playlistId);
    });
  }

  Future<void> _submit(List<Playlist> playlists) async {
    final targets = playlists
        .where((p) => _selectedIds.contains(p.id))
        .toList();
    if (targets.isEmpty) return;

    setState(() => _submitting = true);
    final library = context.read<LibraryProvider>();
    final failures = <String>[];
    await Future.wait(
      targets.map((playlist) async {
        try {
          await library.addTrackToPlaylist(playlist, widget.track);
        } catch (_) {
          failures.add(playlist.title);
        }
      }),
    );
    if (!mounted) return;

    if (failures.isEmpty) {
      AppFlushbar.success(
        context,
        targets.length == 1
            ? 'Added to ${targets.first.title}'
            : 'Added to ${targets.length} playlists',
      );
    } else if (failures.length == targets.length) {
      AppFlushbar.error(context, "Couldn't add to any playlist");
    } else {
      AppFlushbar.error(context, 'Failed for: ${failures.join(', ')}');
    }
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final playlists = context.watch<LibraryProvider>().userPlaylists;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add to playlist',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (playlists.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No playlists yet. Create one to begin.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      final selected = _selectedIds.contains(playlist.id);
                      return CheckboxListTile(
                        value: selected,
                        onChanged: _submitting
                            ? null
                            : (_) => _toggle(playlist.id),
                        controlAffinity: ListTileControlAffinity.trailing,
                        contentPadding: EdgeInsets.zero,
                        secondary: NetworkThumbnail(
                          url: playlist.thumbnailUrl,
                          width: 44,
                          height: 44,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        title: Text(
                          playlist.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        subtitle: Text('${playlist.itemCount} videos'),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_selectedIds.isEmpty || _submitting)
                      ? null
                      : () => _submit(playlists),
                  child: _submitting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : Text(
                          _selectedIds.isEmpty
                              ? 'Select playlists'
                              : 'Add to ${_selectedIds.length} playlist${_selectedIds.length == 1 ? '' : 's'}',
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
