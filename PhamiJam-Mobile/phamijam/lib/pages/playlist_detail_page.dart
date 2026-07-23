import 'package:flutter/material.dart';
import 'package:phamijam/components/add_to_playlist_sheet.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/components/download_action.dart';
import 'package:phamijam/components/edit_playlist_sheet.dart';
import 'package:phamijam/components/like_action.dart';
import 'package:phamijam/components/playlist_pin_action.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/pages/artist_page.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:phamijam/widgets/mini_player.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:phamijam/widgets/swipe_back.dart';
import 'package:phamijam/widgets/track_tile.dart';
import 'package:provider/provider.dart';

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

  @override
  void initState() {
    super.initState();
    _playlist = widget.playlist;
    if (_playlist.tracks.isEmpty && _playlist.itemCount > 0) {
      _loadTracks();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
      if (!mounted) return;
      AppFlushbar.error(context, "Couldn't delete playlist: $error");
    }
  }

  Future<bool> _handleRemoveTrack(Track track) async {
    if (!_playlist.isFromYoutube) {
      try {
        await context.read<LibraryProvider>().toggleLike(track);
        if (!mounted) return false;
        setState(
          () => _playlist = _playlist.copyWith(
            tracks: _playlist.tracks.where((t) => t.id != track.id).toList(),
          ),
        );
        AppFlushbar.success(context, 'Removed from Liked Songs');
        return true;
      } catch (error) {
        if (!mounted) return false;
        AppFlushbar.error(context, "Couldn't remove track: $error");
        return false;
      }
    }

    try {
      final updated = await context
          .read<LibraryProvider>()
          .removeTrackFromPlaylist(_playlist, track);
      if (!mounted) return false;
      setState(() => _playlist = updated);
      AppFlushbar.success(context, 'Removed from playlist');
      return true;
    } catch (error) {
      if (!mounted) return false;
      AppFlushbar.error(context, "Couldn't remove track: $error");
      return false;
    }
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
      if (!mounted) return;
      setState(() {
        _loadingTracks = false;
        _loadError = "Couldn't load tracks for this playlist.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final library = context.watch<LibraryProvider>();
    final downloads = context.watch<DownloadsProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final playlist = _playlist;
    final songCount = playlist.tracks.isNotEmpty
        ? playlist.tracks.length
        : playlist.itemCount;

    final query = _searchQuery.trim().toLowerCase();
    final filteredTracks = query.isEmpty
        ? playlist.tracks
        : playlist.tracks
              .where(
                (t) =>
                    t.title.toLowerCase().contains(query) ||
                    t.artist.toLowerCase().contains(query),
              )
              .toList();

    return SwipeBack(
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
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
                        children: [
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
                          if (playlist.isFromYoutube ||
                              playlist.tracks.isNotEmpty)
                            Builder(
                              builder: (context) {
                                final allDownloaded =
                                    playlist.tracks.isNotEmpty &&
                                    playlist.tracks.every(
                                      (t) => downloads.isDownloaded(t.videoId),
                                    );
                                final anyDownloading = playlist.tracks.any(
                                  (t) => downloads.isDownloading(t.videoId),
                                );
                                return PopupMenuButton<String>(
                                  icon: Icon(
                                    Icons.more_horiz_rounded,
                                    color: colorScheme.onSurface,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _handleEdit();
                                    } else if (value == 'pin') {
                                      _handleTogglePin();
                                    } else if (value == 'delete') {
                                      _handleDelete();
                                    } else if (value == 'download_playlist') {
                                      downloads.downloadPlaylist(
                                        playlist.tracks,
                                      );
                                    } else if (value == 'stop_downloading') {
                                      downloads.cancelAllDownloads();
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    if (playlist.isFromYoutube) ...[
                                      PopupMenuItem(
                                        value: 'pin',
                                        child: ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(
                                            playlist.isPinned
                                                ? Icons
                                                      .push_pin_outlined
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
                                          leading: Icon(Icons.edit_rounded),
                                          title: Text('Edit details'),
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
                                                ? Icons.stop_circle_rounded
                                                : allDownloaded
                                                ? Icons.download_done_rounded
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
                            url: playlist.thumbnailUrl,
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
                              color: player.shuffle
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 24),
                          _PlayButton(
                            onTap: playlist.tracks.isEmpty
                                ? null
                                : () => player.shuffle
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
                              player.repeatMode == PlayerRepeatMode.one
                                  ? Icons.repeat_one_rounded
                                  : Icons.repeat_rounded,
                              color: player.repeatMode == PlayerRepeatMode.off
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
              if (!_loadingTracks &&
                  _loadError == null &&
                  playlist.tracks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _searchQuery = value),
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
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              Padding(
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
                          child: Text(
                            playlist.isFromYoutube
                                ? 'No videos in this playlist'
                                : 'No liked songs yet. Tap the heart on any '
                                      'track to add it here.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
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
                    : Column(
                        children: List.generate(filteredTracks.length, (i) {
                          final track = filteredTracks[i];
                          final originalIndex = playlist.tracks.indexOf(track);
                          return TrackTile(
                            index: i + 1,
                            track: track,
                            isActive: player.currentTrack?.id == track.id,
                            onTap: () => player.playQueue(
                              playlist.tracks,
                              startIndex: originalIndex,
                              sourcePlaylist: playlist,
                            ),
                            onPlayNext: () => player.playNext(track),
                            onRemove: () => _handleRemoveTrack(track),
                            onMore: () =>
                                showAddToPlaylistSheet(context, track),
                            isLiked: library.isLiked(track),
                            onToggleLike: () =>
                                toggleTrackLike(context, track),
                            isDownloaded: downloads.isDownloaded(
                              track.videoId,
                            ),
                            downloadProgress: downloads.progressFor(
                              track.videoId,
                            ),
                            onToggleDownload: () =>
                                toggleTrackDownload(context, track),
                            onCancelDownload: track.videoId == null
                                ? null
                                : () => downloads.cancelDownload(
                                    track.videoId!,
                                  ),
                            onArtistTap: openArtistPageCallback(
                              context,
                              channelId: track.channelId,
                              artistName: track.artist,
                            ),
                          );
                        }),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _PlayButton({required this.onTap});

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
            Icons.play_arrow_rounded,
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
