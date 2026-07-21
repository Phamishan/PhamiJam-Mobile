import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phamijam/components/add_to_playlist_sheet.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/pages/artist_page.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/services/youtube_service.dart';
import 'package:phamijam/widgets/playlist_card.dart';
import 'package:phamijam/widgets/section_header.dart';
import 'package:phamijam/widgets/track_tile.dart';
import 'package:provider/provider.dart';

class SearchPage extends StatefulWidget {
  final String query;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClose;
  final ValueChanged<Playlist> onOpenPlaylist;

  const SearchPage({
    super.key,
    required this.query,
    required this.controller,
    required this.focusNode,
    required this.onQueryChanged,
    required this.onClose,
    required this.onOpenPlaylist,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  Timer? _debounce;
  String _searchedQuery = '';
  List<Track> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != oldWidget.query) {
      _scheduleSearch(widget.query);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _scheduleSearch(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
        _error = null;
        _searchedQuery = '';
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _runSearch(query),
    );
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await YoutubeService.searchVideos(query);
      if (!mounted || query != widget.query) return;
      setState(() {
        _results = results;
        _loading = false;
        _searchedQuery = query;
      });
    } catch (error) {
      if (!mounted || query != widget.query) return;
      setState(() {
        _loading = false;
        _error = "Couldn't search YouTube. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final player = context.read<PlayerProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    Widget child;
    if (widget.query.isEmpty) {
      child = _BrowseView(
        key: const ValueKey('browse'),
        library: library,
        player: player,
        onOpenPlaylist: widget.onOpenPlaylist,
      );
    } else if (_loading) {
      child = const Center(
        key: ValueKey('loading'),
        child: CircularProgressIndicator(),
      );
    } else if (_error != null) {
      child = _ErrorView(
        key: const ValueKey('error'),
        message: _error!,
        onRetry: () => _runSearch(widget.query),
      );
    } else if (_results.isEmpty && _searchedQuery == widget.query) {
      child = _EmptyResults(
        key: const ValueKey('empty'),
        query: widget.query,
        colorScheme: colorScheme,
      );
    } else {
      child = _ResultsView(
        key: const ValueKey('results'),
        query: widget.query,
        tracks: _results,
        player: player,
      );
    }

    return Column(
      children: [
        _SearchBar(
          controller: widget.controller,
          focusNode: widget.focusNode,
          onChanged: widget.onQueryChanged,
          onClose: widget.onClose,
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
            onPressed: onClose,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onChanged: onChanged,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlignVertical: TextAlignVertical.center,
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Search',
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        splashRadius: 16,
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrowseView extends StatelessWidget {
  final LibraryProvider library;
  final PlayerProvider player;
  final ValueChanged<Playlist> onOpenPlaylist;

  const _BrowseView({
    super.key,
    required this.library,
    required this.player,
    required this.onOpenPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Search', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(
            'Search all of YouTube, or browse your playlists below.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 28),
          SectionHeader(title: 'Browse Your Playlists'),
          SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: library.userPlaylists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final playlist = library.userPlaylists[index];
                return PlaylistCard(
                  playlist: playlist,
                  onTap: () => onOpenPlaylist(playlist),
                  onPlay: () => player.playQueue(playlist.tracks),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  final String query;
  final ColorScheme colorScheme;

  const _EmptyResults({
    super.key,
    required this.query,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 44,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No results for "$query"',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 44,
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

class _ResultsView extends StatelessWidget {
  final String query;
  final List<Track> tracks;
  final PlayerProvider player;

  const _ResultsView({
    super.key,
    required this.query,
    required this.tracks,
    required this.player,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Results for "$query"',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          ...List.generate(
            tracks.length,
            (index) => TrackTile(
              track: tracks[index],
              onTap: () => player.playQueue(tracks, startIndex: index),
              onPlayNext: () => player.playNext(tracks[index]),
              onMore: () => showAddToPlaylistSheet(context, tracks[index]),
              onArtistTap: openArtistPageCallback(
                context,
                channelId: tracks[index].channelId,
                artistName: tracks[index].artist,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
