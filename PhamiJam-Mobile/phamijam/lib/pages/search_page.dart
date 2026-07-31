import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phamijam/components/add_to_playlist_sheet.dart';
import 'package:phamijam/components/download_action.dart';
import 'package:phamijam/components/like_action.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/pages/album_details_page.dart';
import 'package:phamijam/pages/artist_page.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:phamijam/services/youtube_service.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:phamijam/widgets/recent_track_card.dart';
import 'package:phamijam/widgets/section_header.dart';
import 'package:phamijam/widgets/track_tile.dart';
import 'package:provider/provider.dart';
import 'package:ytmusicapi_dart/enums.dart';
import 'package:ytmusicapi_dart/navigation.dart';
import 'package:ytmusicapi_dart/parsers/browsing.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

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
  List<Track> _ytmSongs = [];
  List<Map<String, dynamic>> _ytmArtists = [];
  List<Map<String, dynamic>> _ytmAlbums = [];
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
        _ytmSongs = [];
        _ytmArtists = [];
        _ytmAlbums = [];
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

  bool get _hasResults =>
      context.read<SettingsProvider>().searchEngine == SearchEngine.youtube
      ? _results.isNotEmpty
      : (_ytmSongs.isNotEmpty ||
            _ytmArtists.isNotEmpty ||
            _ytmAlbums.isNotEmpty);

  Future<void> _runSearch(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final engine = context.read<SettingsProvider>().searchEngine;
    try {
      if (engine == SearchEngine.youtube) {
        final results = await YoutubeService.searchVideos(query);
        if (!mounted || query != widget.query) return;
        setState(() {
          _results = results;
          _ytmSongs = [];
          _ytmArtists = [];
          _ytmAlbums = [];
          _loading = false;
          _searchedQuery = query;
        });
      } else {
        final ytmusic = await YTMusic.create();
        final lists = await Future.wait([
          ytmusic.search(query, filter: SearchFilter.songs, limit: 12),
          ytmusic.search(query, filter: SearchFilter.artists, limit: 6),
          ytmusic.search(query, filter: SearchFilter.albums, limit: 6),
        ]);
        if (!mounted || query != widget.query) return;
        final songs = lists[0]
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .where((item) => readYtString(item['videoId']).isNotEmpty)
            .map(
              (item) => ytSongToTrack(
                item,
                fallbackArtistName: 'Unknown artist',
                fallbackArtistId: '',
              ),
            )
            .toList();
        setState(() {
          _ytmSongs = songs;
          _ytmArtists = lists[1]
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          _ytmAlbums = lists[2]
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          _results = [];
          _loading = false;
          _searchedQuery = query;
        });
      }
    } catch (error) {
      if (!mounted || query != widget.query) return;
      setState(() {
        _loading = false;
        _error = "Couldn't search right now. Try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final engine = context.watch<SettingsProvider>().searchEngine;

    Widget child;
    if (widget.query.isEmpty) {
      child = _BrowseView(key: const ValueKey('browse'), player: player);
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
    } else if (!_hasResults && _searchedQuery == widget.query) {
      child = _EmptyResults(
        key: const ValueKey('empty'),
        query: widget.query,
        colorScheme: colorScheme,
      );
    } else if (engine == SearchEngine.youtube) {
      child = _ResultsView(
        key: const ValueKey('results'),
        query: widget.query,
        tracks: _results,
        player: player,
      );
    } else {
      child = _YTMusicResultsView(
        key: const ValueKey('ytm-results'),
        query: widget.query,
        songs: _ytmSongs,
        artists: _ytmArtists,
        albums: _ytmAlbums,
        player: player,
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            _SearchBar(
              controller: widget.controller,
              focusNode: widget.focusNode,
              onChanged: widget.onQueryChanged,
              onClose: widget.onClose,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.center,
                child: Consumer<SettingsProvider>(
                  builder: (context, settings, _) {
                    return SegmentedButton<SearchEngine>(
                      segments: const [
                        ButtonSegment(
                          value: SearchEngine.youtubeMusic,
                          label: Text('YouTube Music'),
                          icon: Icon(Icons.music_note_rounded),
                        ),
                        ButtonSegment(
                          value: SearchEngine.youtube,
                          label: Text('YouTube'),
                          icon: Icon(Icons.smart_display_rounded),
                        ),
                      ],
                      selected: {settings.searchEngine},
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: colorScheme.surfaceContainer,
                        foregroundColor: colorScheme.onSurfaceVariant,
                        selectedBackgroundColor: colorScheme.primary,
                        selectedForegroundColor: colorScheme.onPrimary,
                      ),
                      onSelectionChanged: (selection) {
                        settings.setSearchEngine(selection.first);
                        if (widget.query.trim().isNotEmpty) {
                          _runSearch(widget.query);
                        }
                      },
                    );
                  },
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: child,
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: ListenableBuilder(
            listenable: widget.focusNode,
            builder: (context, _) {
              final hasFocus = widget.focusNode.hasFocus;
              return IgnorePointer(
                ignoring: hasFocus,
                child: AnimatedOpacity(
                  opacity: hasFocus ? 0 : 1,
                  duration: const Duration(milliseconds: 150),
                  child: FloatingActionButton.small(
                    heroTag: 'search-page-fab',
                    onPressed: widget.focusNode.requestFocus,
                    child: const Icon(Icons.search_rounded),
                  ),
                ),
              );
            },
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

class _BrowseView extends StatefulWidget {
  final PlayerProvider player;

  const _BrowseView({super.key, required this.player});

  @override
  State<_BrowseView> createState() => _BrowseViewState();
}

class _BrowseViewState extends State<_BrowseView> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _newReleases = const [];
  List<Track> _forYou = const [];
  Map<String, int> _artistSubscriberCounts = const {};
  late final LibraryProvider _library;
  bool _personalizedSignalApplied = false;

  @override
  void initState() {
    super.initState();
    _library = context.read<LibraryProvider>();
    _library.addListener(_handleLibraryChanged);
    _load();
  }

  @override
  void dispose() {
    _library.removeListener(_handleLibraryChanged);
    super.dispose();
  }

  void _handleLibraryChanged() {
    if (_personalizedSignalApplied) return;
    if (_library.likedSongs.isEmpty && _library.recentlyPlayed.isEmpty) {
      return;
    }
    _personalizedSignalApplied = true;
    _load();
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<String> _rankedArtistIds() {
    final counts = <String, int>{};
    void tally(Iterable<Track> tracks) {
      for (final track in tracks) {
        final id = track.channelId;
        if (id == null || id.isEmpty) continue;
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }

    tally(_library.recentlyPlayed);
    tally(_library.likedSongs);
    final ids = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return ids;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ytmusic = await YTMusic.create();
      final seedArtistIds = _rankedArtistIds();
      final excludeVideoIds = <String>{
        for (final track in _library.recentlyPlayed)
          if (track.videoId != null) track.videoId!,
        for (final track in _library.likedSongs)
          if (track.videoId != null) track.videoId!,
      };

      List<Map<String, dynamic>> newReleases = const [];
      List<Track> forYou = const [];
      Object? firstError;

      await Future.wait([
        _fetchNewReleases(
          ytmusic,
        ).then((value) => newReleases = value).catchError((error) {
          firstError ??= error;
          return const <Map<String, dynamic>>[];
        }),
        _fetchForYou(
          ytmusic,
          seedArtistIds,
          excludeVideoIds,
        ).then((value) => forYou = value).catchError((error) {
          firstError ??= error;
          return const <Track>[];
        }),
      ]);

      if (!mounted) return;
      if (newReleases.isEmpty && forYou.isEmpty && firstError != null) {
        setState(() {
          _loading = false;
          _error = "Couldn't load new music right now.";
        });
        return;
      }

      Map<String, int> subscriberCounts = const {};
      if (newReleases.isNotEmpty) {
        try {
          final artistIds = <String>{
            for (final album in newReleases)
              if (album['artists'] is List)
                for (final artist in album['artists'] as List)
                  if (artist is Map && readYtString(artist['id']).isNotEmpty)
                    readYtString(artist['id']),
          }.toList();
          subscriberCounts = await YoutubeService.fetchChannelSubscriberCounts(
            artistIds,
          );
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _newReleases = newReleases;
        _forYou = forYou;
        _artistSubscriberCounts = subscriberCounts;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load new music right now.";
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchNewReleases(YTMusic ytmusic) async {
    final response = await ytmusic.sendRequest('browse', <String, dynamic>{
      'browseId': 'FEmusic_explore',
    });
    final results = nav(response, [...SINGLE_COLUMN_TAB, ...SECTION_LIST]);

    final newReleases = <Map<String, dynamic>>[];
    for (final result in results as Iterable) {
      final browseId =
          nav(result, [
                ...CAROUSEL,
                ...CAROUSEL_TITLE,
                ...NAVIGATION_BROWSE_ID,
              ], nullIfAbsent: true)
              as String?;
      if (browseId != 'FEmusic_new_releases_albums') continue;
      for (final item in nav(result, CAROUSEL_CONTENTS) as List) {
        newReleases.add(parseAlbum(Map<String, dynamic>.from(item as Map)));
      }
      break;
    }
    return newReleases;
  }

  Future<List<Track>> _fetchForYou(
    YTMusic ytmusic,
    List<String> seedArtistIds,
    Set<String> excludeVideoIds,
  ) async {
    final forYou = <Track>[];
    final seenVideoIds = <String>{...excludeVideoIds};

    for (final artistId in seedArtistIds.take(5)) {
      if (forYou.length >= 15) break;
      try {
        final artist = Map<String, dynamic>.from(
          await ytmusic.getArtist(artistId),
        );
        final songsSection = artist['songs'];
        final songs = _asMapList(
          songsSection is Map ? songsSection['results'] : null,
        );
        for (final item in songs.take(4)) {
          final videoId = readYtString(item['videoId']);
          if (videoId.isEmpty || !seenVideoIds.add(videoId)) continue;
          forYou.add(
            ytSongToTrack(
              item,
              fallbackArtistName: 'Unknown artist',
              fallbackArtistId: artistId,
            ),
          );
          if (forYou.length >= 15) break;
        }
      } catch (_) {}
    }

    if (forYou.length >= 8) return forYou;

    final home = List<dynamic>.from(await ytmusic.getHome(limit: 3));
    outer:
    for (final row in home) {
      if (row is! Map) continue;
      for (final item in _asMapList(row['contents'])) {
        final videoId = readYtString(item['videoId']);
        if (videoId.isEmpty || !seenVideoIds.add(videoId)) continue;
        forYou.add(
          ytSongToTrack(
            item,
            fallbackArtistName: 'Unknown artist',
            fallbackArtistId: '',
          ),
        );
        if (forYou.length >= 15) break outer;
      }
    }
    return forYou;
  }

  void _openAlbum(Map<String, dynamic> album) {
    final browseId = readYtString(album['browseId']);
    if (browseId.isEmpty) return;
    final title = readYtString(album['title'], 'Album');
    final artists = album['artists'];
    final firstArtist = (artists is List && artists.isNotEmpty)
        ? artists.first
        : null;
    final artistName = firstArtist is Map
        ? readYtString(firstArtist['name'], 'Unknown artist')
        : 'Unknown artist';
    final artistId = firstArtist is Map ? readYtString(firstArtist['id']) : '';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumDetailsPage(
          albumId: browseId,
          albumTitle: title,
          artistId: artistId,
          artistName: artistName,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _rankByRelevance(Set<String> knownArtistIds) {
    final matches = <Map<String, dynamic>>[];
    final rest = <Map<String, dynamic>>[];
    for (final album in _newReleases) {
      final artists = album['artists'];
      final isMatch =
          knownArtistIds.isNotEmpty &&
          artists is List &&
          artists.any(
            (artist) =>
                artist is Map &&
                knownArtistIds.contains(readYtString(artist['id'])),
          );
      (isMatch ? matches : rest).add(album);
    }
    return [
      ..._stableSortByPopularityDesc(matches),
      ..._stableSortByPopularityDesc(rest),
    ];
  }

  int _popularityOf(Map<String, dynamic> album) {
    final artists = album['artists'];
    if (artists is! List) return 0;
    var best = 0;
    for (final artist in artists) {
      if (artist is! Map) continue;
      final count = _artistSubscriberCounts[readYtString(artist['id'])] ?? 0;
      if (count > best) best = count;
    }
    return best;
  }

  List<Map<String, dynamic>> _stableSortByPopularityDesc(
    List<Map<String, dynamic>> albums,
  ) {
    final indexed = albums.asMap().entries.toList()
      ..sort((a, b) {
        final popularityCompare = _popularityOf(
          b.value,
        ).compareTo(_popularityOf(a.value));
        return popularityCompare != 0
            ? popularityCompare
            : a.key.compareTo(b.key);
      });
    return [for (final entry in indexed) entry.value];
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final downloads = context.watch<DownloadsProvider>();
    final newReleases = _rankByRelevance(_rankedArtistIds().toSet());

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Search', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text(
            'Search all of YouTube, or discover something new below.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 28),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            if (newReleases.isNotEmpty) ...[
              SectionHeader(title: 'New Music'),
              SizedBox(
                height: 210,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: newReleases.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final album = newReleases[index];
                    return _NewReleaseCard(
                      album: album,
                      onTap: () => _openAlbum(album),
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),
            ],
            if (_forYou.isNotEmpty) ...[
              SectionHeader(title: 'For You'),
              SizedBox(
                height: 210,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _forYou.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final track = _forYou[index];
                    return RecentTrackCard(
                      track: track,
                      isActive: widget.player.currentTrack?.id == track.id,
                      onTap: () =>
                          widget.player.playQueue(_forYou, startIndex: index),
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
            ],
          ],
        ],
      ),
    );
  }
}

class _NewReleaseCard extends StatelessWidget {
  final Map<String, dynamic> album;
  final VoidCallback onTap;

  const _NewReleaseCard({required this.album, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = readYtString(album['title'], 'Unknown album');
    final year = readYtString(album['year']);
    final artists = album['artists'];
    final firstArtist = (artists is List && artists.isNotEmpty)
        ? artists.first
        : null;
    final artistName = firstArtist is Map
        ? readYtString(firstArtist['name'], 'Unknown artist')
        : 'Unknown artist';
    final subtitle = [artistName, if (year.isNotEmpty) year].join(' · ');
    final thumbnailUrl = ytThumbnailUrl(album);

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AspectRatio(
                aspectRatio: 1,
                child: NetworkThumbnail(
                  url: thumbnailUrl,
                  fit: BoxFit.cover,
                  iconSize: 32,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
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
    final library = context.watch<LibraryProvider>();
    final downloads = context.watch<DownloadsProvider>();
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
              isLiked: library.isLiked(tracks[index]),
              onToggleLike: () => toggleTrackLike(context, tracks[index]),
              isDownloaded: downloads.isDownloaded(tracks[index].videoId),
              downloadProgress: downloads.progressFor(tracks[index].videoId),
              onToggleDownload: () =>
                  toggleTrackDownload(context, tracks[index]),
              onCancelDownload: tracks[index].videoId == null
                  ? null
                  : () => downloads.cancelDownload(tracks[index].videoId!),
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

class _YTMusicResultsView extends StatelessWidget {
  final String query;
  final List<Track> songs;
  final List<Map<String, dynamic>> artists;
  final List<Map<String, dynamic>> albums;
  final PlayerProvider player;

  const _YTMusicResultsView({
    super.key,
    required this.query,
    required this.songs,
    required this.artists,
    required this.albums,
    required this.player,
  });

  void _openAlbum(BuildContext context, Map<String, dynamic> album) {
    final browseId = readYtString(album['browseId']);
    if (browseId.isEmpty) return;
    final title = readYtString(album['title'], 'Album');
    final albumArtists = album['artists'];
    final firstArtist = (albumArtists is List && albumArtists.isNotEmpty)
        ? albumArtists.first
        : null;
    final artistName = firstArtist is Map
        ? readYtString(firstArtist['name'], 'Unknown artist')
        : 'Unknown artist';
    final artistId = firstArtist is Map ? readYtString(firstArtist['id']) : '';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumDetailsPage(
          albumId: browseId,
          albumTitle: title,
          artistId: artistId,
          artistName: artistName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final downloads = context.watch<DownloadsProvider>();

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
          if (artists.isNotEmpty) ...[
            SectionHeader(title: 'Artists'),
            SizedBox(
              height: 118,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: artists.length,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: (context, index) =>
                    _ArtistResultTile(artist: artists[index]),
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (albums.isNotEmpty) ...[
            SectionHeader(title: 'Albums'),
            SizedBox(
              height: 210,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: albums.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final album = albums[index];
                  return _NewReleaseCard(
                    album: album,
                    onTap: () => _openAlbum(context, album),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
          if (songs.isNotEmpty) ...[
            SectionHeader(title: 'Songs'),
            const SizedBox(height: 8),
            ...List.generate(songs.length, (index) {
              final track = songs[index];
              return TrackTile(
                index: index + 1,
                track: track,
                isActive: player.currentTrack?.id == track.id,
                onTap: () => player.playQueue(songs, startIndex: index),
                onPlayNext: () => player.playNext(track),
                onMore: () => showAddToPlaylistSheet(context, track),
                isLiked: library.isLiked(track),
                onToggleLike: () => toggleTrackLike(context, track),
                isDownloaded: downloads.isDownloaded(track.videoId),
                downloadProgress: downloads.progressFor(track.videoId),
                onToggleDownload: () => toggleTrackDownload(context, track),
                onCancelDownload: track.videoId == null
                    ? null
                    : () => downloads.cancelDownload(track.videoId!),
                onArtistTap: openArtistPageCallback(
                  context,
                  channelId: track.channelId,
                  artistName: track.artist,
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _ArtistResultTile extends StatelessWidget {
  final Map<String, dynamic> artist;

  const _ArtistResultTile({required this.artist});

  @override
  Widget build(BuildContext context) {
    final name = readYtString(artist['artist'], 'Unknown artist');
    final channelId = readYtString(artist['browseId']);
    final thumbnailUrl = ytThumbnailUrl(artist);
    final onTap = openArtistPageCallback(
      context,
      channelId: channelId,
      artistName: name,
    );

    return SizedBox(
      width: 88,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Column(
          children: [
            NetworkThumbnail(
              url: thumbnailUrl,
              width: 80,
              height: 80,
              borderRadius: BorderRadius.circular(999),
              iconSize: 30,
            ),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
