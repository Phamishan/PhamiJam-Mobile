import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phamijam/components/add_to_playlist_sheet.dart';
import 'package:phamijam/components/download_action.dart';
import 'package:phamijam/components/like_action.dart';
import 'package:phamijam/components/playlist_pin_action.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:phamijam/widgets/playlist_card.dart';
import 'package:phamijam/widgets/recent_artists_row.dart';
import 'package:phamijam/widgets/recent_track_card.dart';
import 'package:phamijam/widgets/section_header.dart';
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
    final downloads = context.watch<DownloadsProvider>();
    final player = context.read<PlayerProvider>();
    final settings = context.watch<SettingsProvider>();
    final visiblePlaylists = library.madeForYou
        .where((p) => !settings.isPlaylistHidden(p.id))
        .toList();
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
            if (library.recentlyPlayed.isNotEmpty) ...[
              SectionHeader(title: 'Recently Played Artists'),
              RecentArtistsRow(tracks: library.recentlyPlayed),
              const SizedBox(height: 24),
            ],
            if (visiblePlaylists.isNotEmpty) ...[
              SectionHeader(title: 'Your Playlists', onSeeAll: onOpenLibrary),
              _PlaylistRow(playlists: visiblePlaylists, onOpen: onOpenPlaylist),
            ],
            if (library.recentlyPlayed.isNotEmpty) ...[
              const SizedBox(height: 32),
              SectionHeader(title: 'Jump Back In'),
              Selector<PlayerProvider, String?>(
                selector: (_, player) => player.currentTrack?.id,
                builder: (context, activeTrackId, _) => SizedBox(
                  height: 210,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: library.recentlyPlayed.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final track = library.recentlyPlayed[index];
                      return RecentTrackCard(
                        track: track,
                        isActive: track.id == activeTrackId,
                        onTap: () => player.playQueue(
                          library.recentlyPlayed,
                          startIndex: index,
                        ),
                        onMore: () => showAddToPlaylistSheet(context, track),
                        isLiked: library.isLiked(track),
                        onToggleLike: () => toggleTrackLike(context, track),
                        isDownloaded: downloads.isDownloaded(track.videoId),
                        onToggleDownload: () =>
                            toggleTrackDownload(context, track),
                      );
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
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
            onPlay: () => context.read<PlayerProvider>().playQueue(
              playlist.tracks,
              sourcePlaylist: playlist,
            ),
            onLongPress: () => togglePlaylistPin(context, playlist),
            onTogglePin: () => togglePlaylistPin(context, playlist),
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
