import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phamijam/components/add_to_playlist_sheet.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:phamijam/widgets/playlist_card.dart';
import 'package:phamijam/widgets/section_header.dart';
import 'package:phamijam/widgets/track_tile.dart';
import 'package:provider/provider.dart';

class HomePage extends StatelessWidget {
  final ValueChanged<Playlist> onOpenPlaylist;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenLibrary;

  const HomePage({
    super.key,
    required this.onOpenPlaylist,
    required this.onOpenSearch,
    required this.onOpenLibrary,
  });

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final player = context.read<PlayerProvider>();
    final user = FirebaseAuth.instance.currentUser;
    final firstName = (user?.displayName ?? 'there').split(' ').first;
    final colorScheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surfaceContainerHigh,
      onRefresh: library.refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Welcome back, $firstName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.headlineMedium?.copyWith(fontSize: 22),
                  ),
                ),
                _RoundIconButton(
                  icon: Icons.search_rounded,
                  onTap: onOpenSearch,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _QuickPicksGrid(
              tracks: library.recentlyPlayed.take(6).toList(),
              onTap: (index) =>
                  player.playQueue(library.recentlyPlayed, startIndex: index),
            ),
            const SizedBox(height: 36),
            SectionHeader(title: 'Your Playlists', onSeeAll: onOpenLibrary),
            _PlaylistRow(playlists: library.madeForYou, onOpen: onOpenPlaylist),
            const SizedBox(height: 32),
            SectionHeader(title: 'Recently Played'),
            ...List.generate(
              library.recentlyPlayed.length,
              (index) => TrackTile(
                index: index + 1,
                track: library.recentlyPlayed[index],
                onTap: () =>
                    player.playQueue(library.recentlyPlayed, startIndex: index),
                onPlayNext: () =>
                    player.playNext(library.recentlyPlayed[index]),
                onMore: () => showAddToPlaylistSheet(
                  context,
                  library.recentlyPlayed[index],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _QuickPicksGrid extends StatelessWidget {
  final List<Track> tracks;
  final ValueChanged<int> onTap;

  const _QuickPicksGrid({required this.tracks, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 700 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tracks.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.6,
          ),
          itemBuilder: (context, index) {
            final track = tracks[index];
            final colorScheme = Theme.of(context).colorScheme;
            return Material(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onTap(index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      NetworkThumbnail(
                        url: track.thumbnailUrl,
                        width: 44,
                        height: 44,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          track.title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  final List<Playlist> playlists;
  final ValueChanged<Playlist> onOpen;

  const _PlaylistRow({required this.playlists, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 240,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: playlists.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final playlist = playlists[index];
          return PlaylistCard(
            playlist: playlist,
            onTap: () => onOpen(playlist),
            onPlay: () =>
                context.read<PlayerProvider>().playQueue(playlist.tracks),
          );
        },
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIconButton({required this.icon, required this.onTap});

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
