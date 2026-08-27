import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/components/create_playlist_sheet.dart';
import 'package:phamijam/components/playlist_pin_action.dart';
import 'package:phamijam/components/save_playlist_sheet.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/providers/saved_playlists_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:phamijam/widgets/section_header.dart';
import 'package:provider/provider.dart';

class LibraryPage extends StatefulWidget {
  final ValueChanged<Playlist> onOpenPlaylist;

  const LibraryPage({super.key, required this.onOpenPlaylist});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  void _openLocalFiles(BuildContext context, LibraryProvider library) {
    if (!library.hasConnectedDriveFolder) {
      AppFlushbar.info(
        context,
        'Connect Google Drive in Settings to play your songs.',
      );
      return;
    }
    widget.onOpenPlaylist(library.localFilesPlaylist);
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final savedPlaylists = context.watch<SavedPlaylistsProvider>();
    final settings = context.watch<SettingsProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Your Library',
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(fontSize: 22),
              ),
              Row(
                children: [
                  _ActionIconButton(
                    icon: Icons.bookmark_add_outlined,
                    onTap: () => showSavePlaylistSheet(context),
                  ),
                  const SizedBox(width: 8),
                  _ActionIconButton(
                    icon: Icons.playlist_add_rounded,
                    onTap: () async {
                      final playlist = await showCreatePlaylistSheet(context);
                      if (playlist != null) widget.onOpenPlaylist(playlist);
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: library.isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                : library.errorMessage != null &&
                      library.userPlaylists.isEmpty &&
                      library.likedSongs.isEmpty
                ? _ErrorState(
                    message: library.errorMessage!,
                    onRetry: library.needsGoogleReconnect
                        ? library.connectGoogleAccount
                        : library.refresh,
                    retryLabel: library.needsGoogleReconnect
                        ? 'Connect Google Account'
                        : 'Try again',
                  )
                : _buildContent(context, library, savedPlaylists, settings),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    LibraryProvider library,
    SavedPlaylistsProvider savedPlaylists,
    SettingsProvider settings,
  ) {
    if (library.userPlaylists.isEmpty &&
        library.likedSongs.isEmpty &&
        library.localFiles.isEmpty &&
        savedPlaylists.playlists.isEmpty) {
      return _EmptyState(onRefresh: library.refresh);
    }
    final playlists = library.userPlaylists
        .where((p) => !settings.isPlaylistHidden(p.id))
        .toList();
    final saved = savedPlaylists.playlists;

    return RefreshIndicator(
      onRefresh: () =>
          Future.wait([library.refresh(), savedPlaylists.refresh()]),
      color: Theme.of(context).colorScheme.primary,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: CustomScrollView(
        slivers: [
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.82,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              if (index == 0) {
                return _LikedSongsCard(
                  count: library.likedSongs.length,
                  onTap: () =>
                      widget.onOpenPlaylist(library.likedSongsPlaylist),
                );
              }
              if (index == 1) {
                return _LocalFilesCard(
                  count: library.localFiles.length,
                  onTap: () => _openLocalFiles(context, library),
                );
              }
              final playlist = playlists[index - 2];
              return _LibraryPlaylistTile(
                playlist: playlist,
                onTap: () => widget.onOpenPlaylist(playlist),
                onLongPress: () => togglePlaylistPin(context, playlist),
                onTogglePin: () => togglePlaylistPin(context, playlist),
              );
            }, childCount: playlists.length + 2),
          ),
          if (saved.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: SectionHeader(title: 'Saved Playlists'),
              ),
            ),
            SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.82,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final playlist = saved[index];
                return _LibraryPlaylistTile(
                  playlist: playlist,
                  onTap: () => widget.onOpenPlaylist(playlist),
                  onLongPress: () => savedPlaylists.unsave(playlist.id),
                  onTogglePin: null,
                  onUnsave: () => savedPlaylists.unsave(playlist.id),
                );
              }, childCount: saved.length),
            ),
          ],
          const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
        ],
      ),
    );
  }
}

class _LibraryPlaylistTile extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onTogglePin;
  final VoidCallback? onUnsave;

  const _LibraryPlaylistTile({
    required this.playlist,
    required this.onTap,
    this.onLongPress,
    this.onTogglePin,
    this.onUnsave,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: NetworkThumbnail(
                        url: playlist.thumbnailUrl,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(8),
                        iconSize: 32,
                      ),
                    ),
                    if (playlist.isPinned)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.shadow.withValues(
                                  alpha: 0.45,
                                ),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.push_pin_rounded,
                            color: colorScheme.onPrimary,
                            size: 14,
                          ),
                        ),
                      ),
                    if (onTogglePin != null || onUnsave != null)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: const CircleBorder(),
                          child: PopupMenuButton<String>(
                            splashRadius: 16,
                            borderRadius: BorderRadius.circular(16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            onSelected: (value) {
                              if (value == 'toggle_pin') onTogglePin?.call();
                              if (value == 'unsave') onUnsave?.call();
                            },
                            itemBuilder: (context) => [
                              if (onUnsave != null)
                                const PopupMenuItem(
                                  value: 'unsave',
                                  child: ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      Icons.bookmark_remove_outlined,
                                    ),
                                    title: Text('Remove from saved'),
                                  ),
                                ),
                              if (onTogglePin != null)
                                PopupMenuItem(
                                  value: 'toggle_pin',
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
                            ],
                            child: const Padding(
                              padding: EdgeInsets.all(7),
                              child: Icon(
                                Icons.more_vert_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                playlist.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '${playlist.itemCount} videos',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LikedSongsCard extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _LikedSongsCard({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colorScheme.primary, colorScheme.surfaceContainer],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(
                  child: Icon(
                    Icons.favorite_rounded,
                    color: colorScheme.onPrimary,
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Liked Songs',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '$count songs',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalFilesCard extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _LocalFilesCard({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(
                  child: Icon(
                    Icons.folder_rounded,
                    color: colorScheme.onSurface,
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Google Drive',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '$count songs',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final Future<void> Function() onRefresh;

  const _EmptyState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.library_music_rounded,
            size: 48,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'Your library is empty',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Like a song or create a playlist on YouTube to see it here.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRefresh, child: const Text('Refresh')),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  final String retryLabel;

  const _ErrorState({
    required this.message,
    required this.onRetry,
    this.retryLabel = 'Try again',
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ActionIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHigh,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: colorScheme.onSurface),
        ),
      ),
    );
  }
}
