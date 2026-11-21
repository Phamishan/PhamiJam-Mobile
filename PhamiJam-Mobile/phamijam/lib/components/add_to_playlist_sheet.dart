import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:provider/provider.dart';
import 'package:phamijam/services/log_service.dart';
import 'package:phamijam/services/recent_playlists_prefs.dart';

Future<bool?> showAddToPlaylistSheet(BuildContext context, Track track) {
  return showAddTracksToPlaylistSheet(context, [track]);
}

Future<bool?> showAddTracksToPlaylistSheet(
  BuildContext context,
  List<Track> tracks, {
  String? excludePlaylistId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _AddToPlaylistSheet(
      tracks: tracks,
      excludePlaylistId: excludePlaylistId,
    ),
  );
}

class _AddToPlaylistSheet extends StatefulWidget {
  final List<Track> tracks;
  final String? excludePlaylistId;

  const _AddToPlaylistSheet({required this.tracks, this.excludePlaylistId});

  @override
  State<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

enum _PickerFilter { all, youtube, phamijam }

enum _DuplicateChoice { skip, addAnyway }

class _AddToPlaylistSheetState extends State<_AddToPlaylistSheet> {
  final Set<String> _selectedIds = {};
  bool _submitting = false;
  String _query = '';
  _PickerFilter _filter = _PickerFilter.all;
  List<String> _recentIds = const [];

  @override
  void initState() {
    super.initState();
    RecentPlaylistsPrefs.load().then((ids) {
      if (mounted) setState(() => _recentIds = ids);
    });
  }

  void _toggle(String playlistId) {
    setState(() {
      if (!_selectedIds.remove(playlistId)) _selectedIds.add(playlistId);
    });
  }

  Future<Map<String, Set<String>>> _findDuplicates(
    LibraryProvider library,
    List<Playlist> targets,
  ) async {
    final wanted = widget.tracks
        .map((t) => t.videoId)
        .whereType<String>()
        .toSet();
    final result = <String, Set<String>>{};
    for (final playlist in targets) {
      try {
        final loaded = playlist.isMixed
            ? playlist
            : await library.loadTracks(playlist);
        final present = loaded.tracks
            .map((t) => t.videoId)
            .whereType<String>()
            .toSet();
        final duplicates = wanted.intersection(present);
        if (duplicates.isNotEmpty) result[playlist.id] = duplicates;
      } catch (error) {
        Log.w('library', 'checking for duplicates failed', error);
      }
    }
    return result;
  }

  Future<_DuplicateChoice?> _askAboutDuplicates(
    Map<String, Set<String>> duplicates,
    List<Playlist> targets,
  ) {
    final names = [
      for (final p in targets)
        if (duplicates.containsKey(p.id)) '"${p.title}"',
    ].join(', ');
    final single = widget.tracks.length == 1;
    final message = single
        ? '"${widget.tracks.first.title}" is already in $names.'
        : 'Some of these songs are already in $names.';
    return showDialog<_DuplicateChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Already in the playlist'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_DuplicateChoice.skip),
            child: Text(single ? 'Don\'t add' : 'Skip duplicates'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(_DuplicateChoice.addAnyway),
            child: const Text('Add anyway'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(List<Playlist> playlists) async {
    final targets = playlists
        .where((p) => _selectedIds.contains(p.id))
        .toList();
    if (targets.isEmpty) return;

    setState(() => _submitting = true);
    final library = context.read<LibraryProvider>();

    final duplicates = await _findDuplicates(library, targets);
    var skipDuplicates = false;
    if (duplicates.isNotEmpty) {
      if (!mounted) return;
      final choice = await _askAboutDuplicates(duplicates, targets);
      if (!mounted) return;
      if (choice == null) {
        setState(() => _submitting = false);
        return;
      }
      skipDuplicates = choice == _DuplicateChoice.skip;
    }

    final failures = <String>[];
    var addedAnything = false;
    await Future.wait(
      targets.map((playlist) async {
        final already = duplicates[playlist.id] ?? const <String>{};
        final tracks = skipDuplicates
            ? widget.tracks.where((t) => !already.contains(t.videoId)).toList()
            : widget.tracks;
        if (tracks.isEmpty) return;
        try {
          if (playlist.isMixed) {
            await library.addTracksToMixedPlaylist(
              playlist,
              tracks,
              allowDuplicates: !skipDuplicates,
            );
          } else {
            for (final track in tracks) {
              await library.addTrackToPlaylist(playlist, track);
            }
          }
          addedAnything = true;
        } catch (error) {
          Log.w('library', 'submit failed', error);
          failures.add(playlist.title);
        }
      }),
    );
    if (!mounted) return;

    unawaited(
      RecentPlaylistsPrefs.record(
        targets.where((p) => !failures.contains(p.title)).map((p) => p.id),
      ),
    );
    Navigator.of(context).pop(addedAnything);

    if (failures.isEmpty && !addedAnything) {
      AppFlushbar.info(context, 'Nothing added - already in the playlist.');
    } else if (failures.isEmpty) {
      final destination = targets.length == 1
          ? 'to ${targets.first.title}'
          : 'to ${targets.length} playlists';
      AppFlushbar.success(
        context,
        widget.tracks.length == 1
            ? 'Added $destination'
            : 'Added ${widget.tracks.length} songs $destination',
      );
    } else if (failures.length == targets.length) {
      AppFlushbar.error(context, "Couldn't add to any playlist");
    } else {
      AppFlushbar.error(context, 'Failed for: ${failures.join(', ')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final library = context.watch<LibraryProvider>();
    final settings = context.watch<SettingsProvider>();
    final hasDriveTrack = widget.tracks.any((t) => t.isDriveSourced);
    final playlists =
        [
              if (!hasDriveTrack) ...library.userPlaylists,
              ...library.mixedPlaylists,
            ]
            .where((p) => !settings.isPlaylistHidden(p.id))
            .where((p) => p.id != widget.excludePlaylistId)
            .toList();

    final hasBothKinds =
        playlists.any((p) => p.isMixed) && playlists.any((p) => !p.isMixed);
    final showSearch = playlists.length >= 6;
    final query = _query.trim().toLowerCase();
    final filtered = playlists.where((p) {
      if (_filter == _PickerFilter.youtube && p.isMixed) return false;
      if (_filter == _PickerFilter.phamijam && !p.isMixed) return false;
      return query.isEmpty || p.title.toLowerCase().contains(query);
    }).toList();
    final recent = (query.isEmpty && _filter == _PickerFilter.all)
        ? [
            for (final id in _recentIds)
              ...filtered.where((p) => p.id == id).take(1),
          ].take(3).toList()
        : <Playlist>[];
    final rows = <Object>[
      if (recent.isNotEmpty) ...['Recent', ...recent, 'All playlists'],
      ...filtered.where((p) => !recent.contains(p)),
    ];

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
                          widget.tracks.length == 1
                              ? widget.tracks.first.title
                              : '${widget.tracks.length} songs selected',
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
              if (showSearch)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Search playlists',
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: true,
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHigh,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              if (hasBothKinds)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in const {
                        _PickerFilter.all: 'All',
                        _PickerFilter.youtube: 'YouTube',
                        _PickerFilter.phamijam: 'PhamiJam',
                      }.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: _filter == entry.key,
                          onSelected: (_) =>
                              setState(() => _filter = entry.key),
                        ),
                    ],
                  ),
                ),
              if (playlists.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    hasDriveTrack
                        ? 'Google Drive songs can only go in a PhamiJam '
                              'playlist. Create a Mixed playlist in your '
                              'Library first.'
                        : 'No playlists yet. Create one to begin.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              else if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No playlists match.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      if (row is String) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: Text(
                            row,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        );
                      }
                      final playlist = row as Playlist;
                      final selected = _selectedIds.contains(playlist.id);
                      return CheckboxListTile(
                        value: selected,
                        onChanged: _submitting
                            ? null
                            : (_) => _toggle(playlist.id),
                        controlAffinity: ListTileControlAffinity.trailing,
                        contentPadding: EdgeInsets.zero,
                        secondary: NetworkThumbnail(
                          url: playlist.coverImageUrl,
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
                        subtitle: Text(
                          playlist.isMixed
                              ? '${playlist.itemCount} songs · PhamiJam playlist'
                              : '${playlist.itemCount} videos',
                        ),
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
