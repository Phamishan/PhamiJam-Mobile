import 'package:flutter/material.dart';
import 'package:phamijam/components/create_playlist_sheet.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:provider/provider.dart';

class LibraryPage extends StatefulWidget {
  final ValueChanged<Playlist> onOpenPlaylist;

  const LibraryPage({super.key, required this.onOpenPlaylist});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

enum _LibraryFilter { all, liked }

class _LibraryPageState extends State<LibraryPage> {
  _LibraryFilter _filter = _LibraryFilter.all;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();

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
                    icon: Icons.playlist_add_rounded,
                    tooltip: 'New Playlist',
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
                : library.errorMessage != null
                ? _ErrorState(
                    message: library.errorMessage!,
                    onRetry: library.refresh,
                  )
                : _buildContent(context, library),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, LibraryProvider library) {
    if (_filter == _LibraryFilter.liked) {
      return _LikedSongsCard(
        count: library.likedSongs.length,
        onTap: () => widget.onOpenPlaylist(library.likedSongsPlaylist),
      );
    }

    final playlists = library.userPlaylists;
    if (playlists.isEmpty) {
      return _EmptyState(onRefresh: library.refresh);
    }

    return RefreshIndicator(
      onRefresh: library.refresh,
      color: Theme.of(context).colorScheme.primary,
      child: GridView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: playlists.length + 1,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.82,
        ),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _LikedSongsCard(
              count: library.likedSongs.length,
              onTap: () => widget.onOpenPlaylist(library.likedSongsPlaylist),
            );
          }
          final playlist = playlists[index - 1];
          return _LibraryPlaylistTile(
            playlist: playlist,
            onTap: () => widget.onOpenPlaylist(playlist),
          );
        },
      ),
    );
  }
}

class _LibraryPlaylistTile extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;

  const _LibraryPlaylistTile({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: NetworkThumbnail(
                  url: playlist.thumbnailUrl,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(8),
                  iconSize: 32,
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
            'No YouTube playlists found',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Playlists you create on YouTube will show up here.',
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

  const _ErrorState({required this.message, required this.onRetry});

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
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHigh,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 20, color: colorScheme.onSurface),
          ),
        ),
      ),
    );
  }
}
