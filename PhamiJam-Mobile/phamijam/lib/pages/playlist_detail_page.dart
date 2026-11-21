import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phamijam/components/add_to_playlist_sheet.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/components/download_action.dart';
import 'package:phamijam/components/edit_playlist_sheet.dart';
import 'package:phamijam/components/like_action.dart';
import 'package:phamijam/components/playlist_pin_action.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/pages/artist_page.dart';
import 'package:phamijam/pages/connect_drive_folder_page.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:phamijam/services/profile_service.dart';
import 'package:phamijam/services/share_link_service.dart';
import 'package:phamijam/widgets/mini_player.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:phamijam/widgets/play_button.dart';
import 'package:phamijam/widgets/swipe_back.dart';
import 'package:phamijam/widgets/track_tile.dart';
import 'package:phamijam/services/playlist_sort_prefs.dart';
import 'package:provider/provider.dart';
import 'package:phamijam/services/log_service.dart';
import 'package:phamijam/services/mixed_playlist_service.dart';
import 'package:phamijam/services/unavailable_songs_service.dart';
import 'package:phamijam/services/youtube_service.dart';

enum _PlaylistSort {
  custom,
  dateAddedNewest,
  dateAddedOldest,
  durationShort,
  durationLong,
}

extension on _PlaylistSort {
  String get label {
    switch (this) {
      case _PlaylistSort.custom:
        return 'Playlist order';
      case _PlaylistSort.dateAddedNewest:
        return 'Recently added';
      case _PlaylistSort.dateAddedOldest:
        return 'Oldest added';
      case _PlaylistSort.durationShort:
        return 'Duration (shortest first)';
      case _PlaylistSort.durationLong:
        return 'Duration (longest first)';
    }
  }
}

class PlaylistDetailPage extends StatefulWidget {
  final Playlist playlist;
  final VoidCallback onBack;

  const PlaylistDetailPage({
    super.key,
    required this.playlist,
    required this.onBack,
  });

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  late Playlist _playlist;
  bool _loadingTracks = false;
  String? _loadError;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _selectionMode = false;
  final Set<String> _selectedTrackIds = {};
  _PlaylistSort _sort = _PlaylistSort.custom;
  bool _isFeaturedOnProfile = false;

  int _compareAddedAt(Track a, Track b, {required bool newestFirst}) {
    final da = a.addedAt;
    final db = b.addedAt;
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return newestFirst ? db.compareTo(da) : da.compareTo(db);
  }

  List<Track> _applySort(List<Track> tracks) {
    if (_sort == _PlaylistSort.custom) return tracks;
    final sorted = List<Track>.from(tracks);
    switch (_sort) {
      case _PlaylistSort.custom:
        break;
      case _PlaylistSort.dateAddedNewest:
        sorted.sort((a, b) => _compareAddedAt(a, b, newestFirst: true));
      case _PlaylistSort.dateAddedOldest:
        sorted.sort((a, b) => _compareAddedAt(a, b, newestFirst: false));
      case _PlaylistSort.durationShort:
        sorted.sort((a, b) => a.duration.compareTo(b.duration));
      case _PlaylistSort.durationLong:
        sorted.sort((a, b) => b.duration.compareTo(a.duration));
    }
    return sorted;
  }

  Future<void> _restoreSort() async {
    final saved = await PlaylistSortPrefs.load(widget.playlist.id);
    if (saved == null || !mounted) return;
    final match = _PlaylistSort.values.where((option) => option.name == saved);
    if (match.isNotEmpty) setState(() => _sort = match.first);
  }

  void _selectSort(_PlaylistSort value) {
    setState(() => _sort = value);
    Log.i('library', 'playlist sort -> ${value.name}');
    PlaylistSortPrefs.save(
      widget.playlist.id,
      value.name,
      isDefault: value == _PlaylistSort.custom,
    );
  }

  @override
  void initState() {
    super.initState();
    _restoreSort();
    UnavailableSongs.instance.ensureLoaded();
    UnavailableSongs.instance.addListener(_onUnavailableChanged);
    _playlist = widget.playlist;
    if (_playlist.tracks.isEmpty && _playlist.itemCount > 0) {
      _loadTracks();
    }
    if (_playlist.isFromYoutube && _playlist.isOwnedByUser) {
      _loadFeaturedStatus();
    }
  }

  Future<void> _loadFeaturedStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final ids = await ProfileService.fetchProfilePlaylistIds(user.uid);
      if (!mounted) return;
      setState(() => _isFeaturedOnProfile = ids.contains(_playlist.id));
    } catch (error) {
      Log.w('library', 'load featured status failed', error);
    }
  }

  Future<void> _handleToggleFeatured() async {
    final wasFeatured = _isFeaturedOnProfile;
    setState(() => _isFeaturedOnProfile = !wasFeatured);
    try {
      if (wasFeatured) {
        await ProfileService.removeProfilePlaylist(_playlist.id);
      } else {
        await ProfileService.addProfilePlaylist(_playlist.id);
      }
      if (!mounted) return;
      AppFlushbar.success(
        context,
        wasFeatured ? 'Removed from your profile' : 'Featured on your profile',
      );
    } catch (error) {
      Log.e('library', 'handle toggle featured failed', error);
      if (!mounted) return;
      setState(() => _isFeaturedOnProfile = wasFeatured);
      AppFlushbar.error(context, "Couldn't update your profile: $error");
    }
  }

  @override
  void dispose() {
    UnavailableSongs.instance.removeListener(_onUnavailableChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onUnavailableChanged() {
    if (mounted) setState(() {});
  }

  bool _availabilityChecked = false;

  Future<void> _checkAvailability() async {
    if (_availabilityChecked) return;
    final ids = _playlist.tracks
        .where((t) => !t.isDriveSourced)
        .map((t) => t.videoId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return;
    _availabilityChecked = true;
    try {
      final missing = await YoutubeService.findUnavailableVideos(ids);
      UnavailableSongs.instance.addAll(missing);
      UnavailableSongs.instance.removeAll(
        ids.where((id) => !missing.contains(id)),
      );
      Log.i(
        'library',
        'availability check: ${missing.length} of ${ids.length} songs unavailable',
      );
    } catch (error) {
      Log.w('library', 'availability check failed', error);
    }
  }

  List<Track> _unavailableTracks() => _playlist.tracks
      .where((t) => UnavailableSongs.instance.contains(t.videoId))
      .toList();

  Future<void> _handleEdit() async {
    final updated = await showEditPlaylistSheet(context, _playlist);
    if (updated != null && mounted) {
      setState(() => _playlist = updated);
    }
  }

  Future<void> _handleTogglePin() async {
    await togglePlaylistPin(context, _playlist);
    if (!mounted) return;
    final isPinned = context.read<LibraryProvider>().isPinned(_playlist.id);
    setState(() => _playlist = _playlist.copyWith(isPinned: isPinned));
  }

  Future<void> _handleDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text(
          'This permanently deletes "${_playlist.title}" from your YouTube '
          "account. This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    try {
      await context.read<LibraryProvider>().deletePlaylist(_playlist);
      if (!mounted) return;
      widget.onBack();
    } catch (error) {
      Log.e('library', 'handle delete failed', error);
      if (!mounted) return;
      AppFlushbar.error(context, "Couldn't delete playlist: $error");
    }
  }

  Future<void> _handleRenameMixed() async {
    final controller = TextEditingController(text: _playlist.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newTitle == null || newTitle.isEmpty || !mounted) return;
    try {
      await context.read<LibraryProvider>().renameMixedPlaylist(
        _playlist,
        newTitle,
      );
    } catch (error) {
      Log.e('library', 'handle rename mixed failed', error);
      if (mounted) {
        AppFlushbar.error(context, "Couldn't rename playlist: $error");
      }
    }
  }

  Future<void> _handleChangeMixedCover() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    try {
      await context.read<LibraryProvider>().setPlaylistCover(
        _playlist,
        File(picked.path),
      );
    } catch (error) {
      Log.e('library', 'handle change mixed cover failed', error);
      if (mounted) {
        AppFlushbar.error(context, "Couldn't update cover image: $error");
      }
    }
  }

  Future<void> _handleRemoveMixedCover() async {
    try {
      await context.read<LibraryProvider>().removePlaylistCover(_playlist);
    } catch (error) {
      Log.e('library', 'handle remove mixed cover failed', error);
      if (mounted) {
        AppFlushbar.error(context, "Couldn't remove cover image: $error");
      }
    }
  }

  Future<void> _handleDeleteMixed() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text(
          'This deletes "${_playlist.title}" from PhamiJam. The songs '
          'themselves are not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final export = await MixedPlaylistService.exportPlaylist(_playlist.id);
      final title = _playlist.title;
      if (!mounted) return;
      final toastContext = Navigator.of(context, rootNavigator: true).context;
      await context.read<LibraryProvider>().deleteMixedPlaylist(_playlist);
      if (!mounted) return;
      widget.onBack();
      if (export != null && toastContext.mounted) {
        AppFlushbar.undo(
          toastContext,
          'Deleted "$title"',
          onUndo: () {
            MixedPlaylistService.restorePlaylist(export).catchError((
              Object error,
            ) {
              Log.w('library', 'undo delete failed', error);
              return '';
            });
          },
        );
      }
    } catch (error) {
      Log.e('library', 'handle delete mixed failed', error);
      if (mounted) {
        AppFlushbar.error(context, "Couldn't delete playlist: $error");
      }
    }
  }

  Future<bool> _handleRemoveTrack(Track track) async {
    final tracks = _playlist.tracks;
    final position = tracks.indexWhere((t) => t.id == track.id);
    final beforeId = position >= 0 && position + 1 < tracks.length
        ? tracks[position + 1].videoId
        : null;
    final playlist = _playlist;

    if (playlist.isMixed) {
      try {
        await context.read<LibraryProvider>().removeTrackFromMixedPlaylist(
          playlist,
          track,
        );
        if (!mounted) return false;
        AppFlushbar.undo(
          context,
          'Removed "${track.title}"',
          onUndo: () {
            MixedPlaylistService.insertTrackBefore(
              playlist.id,
              track,
              beforeVideoId: beforeId,
            ).catchError((Object error) {
              Log.w('library', 'undo remove failed', error);
            });
          },
        );
        return true;
      } catch (error) {
        Log.e('library', 'handle remove track failed', error);
        if (!mounted) return false;
        AppFlushbar.error(context, "Couldn't remove track: $error");
        return false;
      }
    }
    if (!playlist.isFromYoutube) {
      try {
        await context.read<LibraryProvider>().toggleLike(track);
        if (!mounted) return false;
        setState(
          () => _playlist = _playlist.copyWith(
            tracks: _playlist.tracks.where((t) => t.id != track.id).toList(),
          ),
        );
        AppFlushbar.undo(
          context,
          'Removed "${track.title}" from Liked Songs',
          onUndo: () => _restoreTracks(playlist, [track]),
        );
        return true;
      } catch (error) {
        Log.e('library', 'handle remove track failed', error);
        if (!mounted) return false;
        AppFlushbar.error(context, "Couldn't remove track: $error");
        return false;
      }
    }

    try {
      final updated = await context
          .read<LibraryProvider>()
          .removeTrackFromPlaylist(playlist, track);
      if (!mounted) return false;
      setState(() => _playlist = updated);
      AppFlushbar.undo(
        context,
        'Removed "${track.title}"',
        onUndo: () => _restoreTracks(playlist, [track]),
      );
      return true;
    } catch (error) {
      Log.e('library', 'handle remove track failed', error);
      if (!mounted) return false;
      AppFlushbar.error(context, "Couldn't remove track: $error");
      return false;
    }
  }

  Future<void> _restoreTracks(Playlist playlist, List<Track> tracks) async {
    final library = context.read<LibraryProvider>();
    try {
      if (playlist.isMixed) {
        await library.addTracksToMixedPlaylist(playlist, tracks);
      } else if (playlist.isFromYoutube) {
        for (final track in tracks) {
          await library.addTrackToPlaylist(playlist, track);
        }
        if (!mounted) return;
        final fresh = library.userPlaylists.where((p) => p.id == playlist.id);
        if (fresh.isNotEmpty) setState(() => _playlist = fresh.first);
      } else {
        for (final track in tracks) {
          await library.toggleLike(track);
        }
        if (!mounted) return;
        setState(
          () => _playlist = _playlist.copyWith(
            tracks: [..._playlist.tracks, ...tracks],
          ),
        );
      }
    } catch (error) {
      Log.e('library', 'undo remove failed', error);
      if (mounted) AppFlushbar.error(context, "Couldn't undo: $error");
    }
  }

  Future<void> _removeTracksWithUndo(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    final library = context.read<LibraryProvider>();
    final playlist = _playlist;
    try {
      if (playlist.isMixed) {
        await MixedPlaylistService.removeVideoIds(
          playlist.id,
          tracks.map((t) => t.videoId).whereType<String>().toSet(),
        );
      } else if (playlist.isFromYoutube) {
        var current = playlist;
        for (final track in tracks) {
          current = await library.removeTrackFromPlaylist(current, track);
        }
        if (!mounted) return;
        setState(() => _playlist = current);
      } else {
        for (final track in tracks) {
          await library.toggleLike(track);
        }
        if (!mounted) return;
        final removedIds = tracks.map((t) => t.id).toSet();
        setState(
          () => _playlist = _playlist.copyWith(
            tracks: _playlist.tracks
                .where((t) => !removedIds.contains(t.id))
                .toList(),
          ),
        );
      }
    } catch (error) {
      Log.e('library', 'removing several songs failed', error);
      if (mounted) AppFlushbar.error(context, "Couldn't remove songs: $error");
      return;
    }
    if (!mounted) return;
    _exitSelectionMode();
    AppFlushbar.undo(
      context,
      tracks.length == 1
          ? 'Removed "${tracks.first.title}"'
          : 'Removed ${tracks.length} songs',
      onUndo: () => _restoreTracks(playlist, tracks),
    );
  }

  Future<void> _removeSelected() => _removeTracksWithUndo(
    _playlist.tracks.where((t) => _selectedTrackIds.contains(t.id)).toList(),
  );

  Future<void> _removeUnavailable() async {
    final broken = _unavailableTracks();
    if (broken.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove unavailable songs?'),
        content: Text(
          '${broken.length} song${broken.length == 1 ? '' : 's'} can no '
          'longer be played on YouTube and '
          '${broken.length == 1 ? 'will be' : 'will be'} removed from '
          '"${_playlist.title}". You can undo this right after.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _removeTracksWithUndo(broken);
  }

  Future<void> _moveSelected() async {
    final selected = _playlist.tracks
        .where((t) => _selectedTrackIds.contains(t.id))
        .toList();
    if (selected.isEmpty) return;
    final added = await showAddTracksToPlaylistSheet(
      context,
      selected,
      excludePlaylistId: _playlist.id,
    );
    if (added != true || !mounted) return;
    await _removeTracksWithUndo(selected);
  }

  void _reorder(int oldIndex, int newIndex) {
    final tracks = _playlist.tracks;
    if (oldIndex < 0 || oldIndex >= tracks.length) return;
    final moved = tracks[oldIndex];
    final videoId = moved.videoId;
    if (videoId == null || newIndex == oldIndex) return;
    final remaining = [...tracks]..removeAt(oldIndex);
    final before = newIndex < remaining.length
        ? remaining[newIndex].videoId
        : null;
    MixedPlaylistService.moveVideo(
      _playlist.id,
      videoId,
      beforeVideoId: before,
    ).catchError((Object error) {
      Log.w('library', 'reordering failed', error);
    });
  }

  void _enterSelectionMode(Track track) {
    setState(() {
      _selectionMode = true;
      _selectedTrackIds
        ..clear()
        ..add(track.id);
    });
  }

  void _toggleTrackSelection(Track track) {
    setState(() {
      if (!_selectedTrackIds.remove(track.id)) {
        _selectedTrackIds.add(track.id);
      }
      if (_selectedTrackIds.isEmpty) _selectionMode = false;
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedTrackIds.clear();
    });
  }

  Future<void> _addSelectedToPlaylist() async {
    final selectedTracks = _playlist.tracks
        .where((t) => _selectedTrackIds.contains(t.id))
        .toList();
    if (selectedTracks.isEmpty) return;
    await showAddTracksToPlaylistSheet(context, selectedTracks);
    if (!mounted) return;
    _exitSelectionMode();
  }

  Future<void> _loadTracks() async {
    setState(() {
      _loadingTracks = true;
      _loadError = null;
    });
    try {
      final hydrated = await context.read<LibraryProvider>().loadTracks(
        _playlist,
      );
      if (!mounted) return;
      setState(() {
        _playlist = hydrated;
        _loadingTracks = false;
      });
    } catch (error) {
      Log.e('library', 'load tracks failed', error);
      if (!mounted) return;
      setState(() {
        _loadingTracks = false;
        _loadError = "Couldn't load tracks for this playlist.";
      });
    }
  }

  Future<void> _refreshLocalFiles() async {
    setState(() => _loadingTracks = true);
    final library = context.read<LibraryProvider>();
    await library.refreshLocalFiles();
    if (!mounted) return;
    setState(() {
      _playlist = library.localFilesPlaylist;
      _loadingTracks = false;
    });
  }

  Future<void> _connectDriveFolder() async {
    final connected = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ConnectDriveFolderPage()),
    );
    if (connected == true) {
      await _refreshLocalFiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerProvider>();
    final isPlaying = context.select<PlayerProvider, bool>((p) => p.isPlaying);
    final currentTrackId = context.select<PlayerProvider, String?>(
      (p) => p.currentTrack?.id,
    );
    final isShuffled = context.select<PlayerProvider, bool>((p) => p.shuffle);
    final repeatMode = context.select<PlayerProvider, PlayerRepeatMode>(
      (p) => p.repeatMode,
    );
    final library = context.watch<LibraryProvider>();
    final downloads = context.watch<DownloadsProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    if (_playlist.isMixed) {
      final live = library.mixedPlaylistById(_playlist.id);
      if (live != null) _playlist = live;
    }
    final playlist = _playlist;
    final songCount = playlist.tracks.isNotEmpty
        ? playlist.tracks.length
        : playlist.itemCount;

    final query = _searchQuery.trim().toLowerCase();
    final searchedTracks = query.isEmpty
        ? playlist.tracks
        : playlist.tracks
              .where(
                (t) =>
                    t.title.toLowerCase().contains(query) ||
                    t.artist.toLowerCase().contains(query),
              )
              .toList();
    final filteredTracks = _applySort(searchedTracks);
    final isThisPlaylistPlaying =
        isPlaying &&
        currentTrackId != null &&
        playlist.tracks.any((t) => t.id == currentTrackId);

    if (!_availabilityChecked &&
        !_loadingTracks &&
        playlist.tracks.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkAvailability());
    }
    final unavailableCount = UnavailableSongs.instance.countIn(
      playlist.tracks.map((t) => t.videoId),
    );
    final canReorder =
        playlist.isMixed &&
        playlist.isOwnedByUser &&
        _sort == _PlaylistSort.custom &&
        query.isEmpty &&
        !_selectionMode;

    Widget tileFor(BuildContext context, int i, {bool reorder = false}) {
      final track = filteredTracks[i];
      final originalIndex = playlist.tracks.indexOf(track);
      return TrackTile(
        index: i + 1,
        track: track,
        isActive: currentTrackId == track.id,
        selectionMode: _selectionMode,
        selected: _selectedTrackIds.contains(track.id),
        onTap: _selectionMode
            ? () => _toggleTrackSelection(track)
            : () => player.playQueue(
                playlist.tracks,
                startIndex: originalIndex,
                sourcePlaylist: playlist,
              ),
        onLongPress: _selectionMode
            ? () => _toggleTrackSelection(track)
            : () => _enterSelectionMode(track),
        onPlayNext: () => player.playNext(track),
        onAddToQueue: () => player.addToQueue(track),
        onRemove: playlist.isOwnedByUser
            ? () => _handleRemoveTrack(track)
            : null,
        onMore: () => _selectionMode && _selectedTrackIds.isNotEmpty
            ? _addSelectedToPlaylist()
            : showAddToPlaylistSheet(context, track),
        isLiked: library.isLiked(track),
        onToggleLike: () => toggleTrackLike(context, track),
        isDownloaded: downloads.isDownloaded(track.videoId),
        downloadProgress: track.isDriveSourced
            ? null
            : downloads.progressFor(track.videoId),
        onToggleDownload: track.isDriveSourced
            ? null
            : () => toggleTrackDownload(context, track),
        onCancelDownload: track.isDriveSourced || track.videoId == null
            ? null
            : () => downloads.cancelDownload(track.videoId!),
        onArtistTap: openArtistPageCallback(
          context,
          channelId: track.channelId,
          artistName: track.artist,
        ),
        playlistId: playlist.id,
        playlistName: playlist.title,
        unavailable: UnavailableSongs.instance.contains(track.videoId),
        reorderIndex: reorder ? i : null,
      );
    }

    return SwipeBack(
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primary.withValues(alpha: 0.35),
                      colorScheme.surface,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: _selectionMode
                            ? [
                                InkWell(
                                  onTap: _exitSelectionMode,
                                  borderRadius: BorderRadius.circular(20),
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${_selectedTrackIds.length} selected',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      onPressed: _selectedTrackIds.isEmpty
                                          ? null
                                          : _addSelectedToPlaylist,
                                      icon: Icon(
                                        Icons.playlist_add_rounded,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                    if (playlist.isOwnedByUser &&
                                        (playlist.isMixed ||
                                            playlist.isFromYoutube)) ...[
                                      IconButton(
                                        onPressed: _selectedTrackIds.isEmpty
                                            ? null
                                            : _moveSelected,
                                        icon: Icon(
                                          Icons.drive_file_move_outlined,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ],
                                    if (playlist.isOwnedByUser)
                                      IconButton(
                                        onPressed: _selectedTrackIds.isEmpty
                                            ? null
                                            : _removeSelected,
                                        icon: Icon(
                                          Icons.delete_outline_rounded,
                                          color: colorScheme.error,
                                        ),
                                      ),
                                  ],
                                ),
                              ]
                            : [
                                InkWell(
                                  onTap: widget.onBack,
                                  borderRadius: BorderRadius.circular(20),
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Icon(
                                      Icons.arrow_back_rounded,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                if (playlist.id == kLocalFilesPlaylistId) ...[
                                  const Spacer(),
                                  IconButton(
                                    onPressed: library.hasConnectedDriveFolder
                                        ? _refreshLocalFiles
                                        : _connectDriveFolder,
                                    icon: Icon(
                                      library.hasConnectedDriveFolder
                                          ? Icons.refresh_rounded
                                          : Icons.add_to_drive_rounded,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ] else if (playlist.isMixed)
                                  PopupMenuButton<String>(
                                    tooltip: '',
                                    icon: Icon(
                                      Icons.more_horiz_rounded,
                                      color: colorScheme.onSurface,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    onSelected: (value) {
                                      if (value == 'rename') {
                                        _handleRenameMixed();
                                      } else if (value == 'cover') {
                                        _handleChangeMixedCover();
                                      } else if (value == 'remove_cover') {
                                        _handleRemoveMixedCover();
                                      } else if (value == 'delete') {
                                        _handleDeleteMixed();
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'rename',
                                        child: ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(Icons.edit_rounded),
                                          title: Text('Rename'),
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'cover',
                                        child: ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(Icons.image_rounded),
                                          title: Text('Change cover image'),
                                        ),
                                      ),
                                      if (playlist.customCoverUrl != null &&
                                          playlist.customCoverUrl!.isNotEmpty)
                                        const PopupMenuItem(
                                          value: 'remove_cover',
                                          child: ListTile(
                                            contentPadding: EdgeInsets.zero,
                                            leading: Icon(
                                              Icons.hide_image_rounded,
                                            ),
                                            title: Text('Remove custom cover'),
                                          ),
                                        ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(Icons.delete_rounded),
                                          title: Text('Delete playlist'),
                                        ),
                                      ),
                                    ],
                                  )
                                else if ((playlist.isFromYoutube &&
                                        playlist.isOwnedByUser) ||
                                    playlist.tracks.isNotEmpty)
                                  Builder(
                                    builder: (context) {
                                      final allDownloaded =
                                          playlist.tracks.isNotEmpty &&
                                          playlist.tracks.every(
                                            (t) => downloads.isDownloaded(
                                              t.videoId,
                                            ),
                                          );
                                      final anyDownloading = playlist.tracks
                                          .any(
                                            (t) => downloads.isDownloading(
                                              t.videoId,
                                            ),
                                          );
                                      return PopupMenuButton<String>(
                                        tooltip: '',
                                        icon: Icon(
                                          Icons.more_horiz_rounded,
                                          color: colorScheme.onSurface,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        onSelected: (value) {
                                          if (value == 'edit') {
                                            _handleEdit();
                                          } else if (value == 'pin') {
                                            _handleTogglePin();
                                          } else if (value == 'delete') {
                                            _handleDelete();
                                          } else if (value ==
                                              'download_playlist') {
                                            downloads.downloadPlaylist(
                                              playlist.tracks,
                                            );
                                          } else if (value ==
                                              'stop_downloading') {
                                            downloads.cancelAllDownloads();
                                          } else if (value == 'share') {
                                            ShareLinkService.sharePlaylist(
                                              context,
                                              playlist,
                                            );
                                          } else if (value == 'feature') {
                                            _handleToggleFeatured();
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          if (playlist.id.isNotEmpty &&
                                              !playlist.isPrivate)
                                            const PopupMenuItem(
                                              value: 'share',
                                              child: ListTile(
                                                contentPadding: EdgeInsets.zero,
                                                leading: Icon(
                                                  Icons.share_rounded,
                                                ),
                                                title: Text('Share'),
                                              ),
                                            ),
                                          if (playlist.isFromYoutube &&
                                              playlist.isOwnedByUser) ...[
                                            PopupMenuItem(
                                              value: 'feature',
                                              child: ListTile(
                                                contentPadding: EdgeInsets.zero,
                                                leading: Icon(
                                                  _isFeaturedOnProfile
                                                      ? Icons.star_rounded
                                                      : Icons
                                                            .star_border_rounded,
                                                ),
                                                title: Text(
                                                  _isFeaturedOnProfile
                                                      ? 'Remove from profile'
                                                      : 'Feature on profile',
                                                ),
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'pin',
                                              child: ListTile(
                                                contentPadding: EdgeInsets.zero,
                                                leading: Icon(
                                                  playlist.isPinned
                                                      ? Icons.push_pin_outlined
                                                      : Icons.push_pin_rounded,
                                                ),
                                                title: Text(
                                                  playlist.isPinned
                                                      ? 'Unpin playlist'
                                                      : 'Pin playlist',
                                                ),
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'edit',
                                              child: ListTile(
                                                contentPadding: EdgeInsets.zero,
                                                leading: Icon(
                                                  Icons.edit_rounded,
                                                ),
                                                title: Text('Edit details'),
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: ListTile(
                                                contentPadding: EdgeInsets.zero,
                                                leading: Icon(
                                                  Icons.delete_rounded,
                                                ),
                                                title: Text('Delete playlist'),
                                              ),
                                            ),
                                          ],
                                          if (playlist.tracks.isNotEmpty)
                                            PopupMenuItem(
                                              value: anyDownloading
                                                  ? 'stop_downloading'
                                                  : 'download_playlist',
                                              enabled: !allDownloaded,
                                              child: ListTile(
                                                contentPadding: EdgeInsets.zero,
                                                leading: Icon(
                                                  anyDownloading
                                                      ? Icons
                                                            .stop_circle_rounded
                                                      : allDownloaded
                                                      ? Icons
                                                            .download_done_rounded
                                                      : Icons.download_rounded,
                                                ),
                                                title: Text(
                                                  anyDownloading
                                                      ? 'Stop downloading'
                                                      : allDownloaded
                                                      ? 'Playlist downloaded'
                                                      : 'Download playlist',
                                                ),
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  )
                                else
                                  const SizedBox(width: 48),
                              ],
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: NetworkThumbnail(
                            url: playlist.coverImageUrl,
                            fit: BoxFit.cover,
                            borderRadius: BorderRadius.circular(12),
                            iconSize: 40,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'PLAYLIST',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        playlist.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.headlineMedium?.copyWith(fontSize: 26),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        playlist.subtitle,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$songCount songs',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: playlist.tracks.isEmpty
                                ? null
                                : player.toggleShuffle,
                            icon: Icon(
                              Icons.shuffle_rounded,
                              color: isShuffled
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 24),
                          PlayButton(
                            isPlaying: isThisPlaylistPlaying,
                            onTap: playlist.tracks.isEmpty
                                ? null
                                : () => isThisPlaylistPlaying
                                      ? player.togglePlayPause()
                                      : isShuffled
                                      ? player.shufflePlay(
                                          playlist.tracks,
                                          sourcePlaylist: playlist,
                                        )
                                      : player.playQueue(
                                          playlist.tracks,
                                          sourcePlaylist: playlist,
                                        ),
                          ),
                          const SizedBox(width: 24),
                          IconButton(
                            onPressed: player.cycleRepeatMode,
                            icon: Icon(
                              repeatMode == PlayerRepeatMode.one
                                  ? Icons.repeat_one_rounded
                                  : Icons.repeat_rounded,
                              color: repeatMode == PlayerRepeatMode.off
                                  ? colorScheme.onSurfaceVariant
                                  : colorScheme.primary,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!_loadingTracks &&
                _loadError == null &&
                playlist.tracks.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) =>
                              setState(() => _searchQuery = value),
                          style: Theme.of(context).textTheme.bodyMedium,
                          decoration: InputDecoration(
                            hintText: 'Search in playlist',
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            suffixIcon: _searchQuery.isEmpty
                                ? null
                                : IconButton(
                                    icon: Icon(
                                      Icons.close_rounded,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    onPressed: () => setState(() {
                                      _searchController.clear();
                                      _searchQuery = '';
                                    }),
                                  ),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHigh,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<_PlaylistSort>(
                        tooltip: '',
                        initialValue: _sort,
                        onSelected: _selectSort,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        icon: Icon(
                          _sort == _PlaylistSort.custom
                              ? Icons.sort_rounded
                              : Icons.filter_list_rounded,
                          color: _sort == _PlaylistSort.custom
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.primary,
                        ),
                        itemBuilder: (context) => [
                          for (final option in _PlaylistSort.values)
                            PopupMenuItem(
                              value: option,
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: option == _sort
                                    ? Icon(
                                        Icons.check_rounded,
                                        color: colorScheme.primary,
                                      )
                                    : const SizedBox(width: 24),
                                title: Text(option.label),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (_loadingTracks || _loadError != null || filteredTracks.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                  child: _loadingTracks
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : _loadError != null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _loadError!,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: _loadTracks,
                                  child: const Text('Try again'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : playlist.tracks.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: playlist.id == kLocalFilesPlaylistId
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        library.hasConnectedDriveFolder
                                            ? 'No songs found in your '
                                                  '"PhamiJam" Drive folder yet.'
                                            : 'Connect a Google Drive folder '
                                                  'named "PhamiJam" to play '
                                                  'songs you keep there.',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                      ),
                                      const SizedBox(height: 12),
                                      OutlinedButton(
                                        onPressed:
                                            library.hasConnectedDriveFolder
                                            ? _refreshLocalFiles
                                            : _connectDriveFolder,
                                        child: Text(
                                          library.hasConnectedDriveFolder
                                              ? 'Refresh'
                                              : 'Connect Google Drive folder',
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    playlist.isMixed
                                        ? 'No songs yet. Use the playlist-add '
                                              'button on any song, including '
                                              'Google Drive songs, to add it '
                                              'here.'
                                        : playlist.isFromYoutube
                                        ? 'No videos in this playlist'
                                        : 'No liked songs yet. Tap the heart '
                                              'on any track to add it here.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                          ),
                        )
                      : filteredTracks.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text(
                              'No songs match "${_searchQuery.trim()}"',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            if (unavailableCount > 0 &&
                playlist.isOwnedByUser &&
                !_selectionMode &&
                !_loadingTracks)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Material(
                    color: colorScheme.errorContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: colorScheme.error,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$unavailableCount song'
                              '${unavailableCount == 1 ? ' is' : 's are'} '
                              'no longer available',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          TextButton(
                            onPressed: _removeUnavailable,
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (!_loadingTracks &&
                _loadError == null &&
                filteredTracks.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                sliver: canReorder
                    ? SliverReorderableList(
                        itemCount: filteredTracks.length,
                        onReorderItem: _reorder,
                        proxyDecorator: (child, index, animation) =>
                            Material(color: Colors.transparent, child: child),
                        itemBuilder: (context, i) => KeyedSubtree(
                          key: ValueKey('reorder-${filteredTracks[i].id}'),
                          child: tileFor(context, i, reorder: true),
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => tileFor(context, i),
                          childCount: filteredTracks.length,
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
