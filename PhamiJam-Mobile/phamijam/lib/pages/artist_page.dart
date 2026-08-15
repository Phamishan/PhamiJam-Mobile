import 'package:flutter/material.dart';
import 'package:phamijam/components/add_to_playlist_sheet.dart';
import 'package:phamijam/components/download_action.dart';
import 'package:phamijam/components/like_action.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/pages/album_details_page.dart';
import 'package:phamijam/pages/youtube_channel_page.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:phamijam/widgets/mini_player.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:phamijam/widgets/swipe_back.dart';
import 'package:phamijam/widgets/track_tile.dart';
import 'package:provider/provider.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

VoidCallback? openArtistPageCallback(
  BuildContext context, {
  required String? channelId,
  required String artistName,
}) {
  if (channelId == null || channelId.isEmpty) return null;
  return () {
    final engine = context.read<SettingsProvider>().searchEngine;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => engine == SearchEngine.youtube
            ? YoutubeChannelPage(channelId: channelId, channelName: artistName)
            : ArtistPage(channelId: channelId, artistName: artistName),
      ),
    );
  };
}

String readYtString(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

String ytThumbnailUrl(Map<String, dynamic> item) {
  final direct = readYtString(item['thumbnailUrl']);
  if (direct.isNotEmpty) return direct;

  final thumbnails = item['thumbnails'];
  if (thumbnails is List) {
    for (final thumbnail in thumbnails) {
      if (thumbnail is Map) {
        final url = readYtString(thumbnail['url']);
        if (url.isNotEmpty) return url;
      }
    }
  }
  return '';
}

String _labelCount(String value, String label) {
  if (value.isEmpty) return value;
  if (value.toLowerCase().contains(label)) return value;
  return '$value $label';
}

Duration ytSongDuration(Map<String, dynamic> item) {
  final seconds = item['duration_seconds'] ?? item['durationSeconds'];
  if (seconds is int) return Duration(seconds: seconds);
  final raw = item['duration'];
  if (raw is String && raw.contains(':')) {
    var total = 0;
    for (final part in raw.split(':')) {
      total = total * 60 + (int.tryParse(part) ?? 0);
    }
    return Duration(seconds: total);
  }
  return Duration.zero;
}

Track ytSongToTrack(
  Map<String, dynamic> item, {
  required String fallbackArtistName,
  required String fallbackArtistId,
  String? fallbackThumbnailUrl,
}) {
  final videoId = readYtString(item['videoId']);
  final artists = item['artists'];
  var artistName = fallbackArtistName;
  String? artistId;
  if (artists is List && artists.isNotEmpty) {
    final first = artists.first;
    if (first is Map) {
      final name = readYtString(first['name']);
      if (name.isNotEmpty) artistName = name;
      final id = readYtString(first['id']);
      if (id.isNotEmpty) artistId = id;
    }
  }
  var thumbnailUrl = ytThumbnailUrl(item);
  if (thumbnailUrl.isEmpty) thumbnailUrl = fallbackThumbnailUrl ?? '';

  return Track(
    id: videoId.isEmpty ? item.hashCode.toString() : 'yt-$videoId',
    title: readYtString(item['title'], 'Unknown song'),
    artist: artistName,
    thumbnailUrl: thumbnailUrl,
    duration: ytSongDuration(item),
    videoId: videoId.isEmpty ? null : videoId,
    channelId: artistId ?? fallbackArtistId,
  );
}

class ArtistPage extends StatefulWidget {
  final String channelId;
  final String artistName;

  const ArtistPage({
    super.key,
    required this.channelId,
    required this.artistName,
  });

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  static const int displaySongsLimit = 5;

  Map<String, dynamic>? _artist;
  List<Track> _songs = const [];
  List<Map<String, dynamic>> _albums = const [];
  List<Map<String, dynamic>> _singles = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ytmusic = await YTMusic.create();
      final artist = Map<String, dynamic>.from(
        await ytmusic.getArtist(widget.channelId),
      );

      const playableSongsLimit = 50;
      final songsSection = artist['songs'];
      final songsBrowseId = songsSection is Map
          ? readYtString(songsSection['browseId'])
          : '';
      List<Map<String, dynamic>> songResults;
      if (songsBrowseId.isNotEmpty) {
        try {
          final playlist = Map<String, dynamic>.from(
            await ytmusic.getPlaylist(songsBrowseId, limit: playableSongsLimit),
          );
          songResults = _asMapList(playlist['tracks']);
        } catch (_) {
          songResults = _asMapList(
            songsSection is Map ? songsSection['results'] : null,
          );
        }
      } else {
        songResults = _asMapList(
          songsSection is Map ? songsSection['results'] : null,
        );
      }

      final albumsSection = artist['albums'];
      final singlesSection = artist['singles'];
      final albums = <Map<String, dynamic>>[];
      final singles = <Map<String, dynamic>>[];

      if (albumsSection is Map) {
        final browseId = readYtString(albumsSection['browseId']);
        final params = readYtString(albumsSection['params']);
        if (browseId.isNotEmpty && params.isNotEmpty) {
          final results = await ytmusic.getArtistAlbums(
            browseId,
            params,
            limit: 12,
          );
          albums.addAll(
            results.whereType<Map>().map(
              (item) => Map<String, dynamic>.from(item),
            ),
          );
        } else {
          albums.addAll(_asMapList(albumsSection['results']));
        }
      }

      if (singlesSection is Map) {
        final browseId = readYtString(singlesSection['browseId']);
        final params = readYtString(singlesSection['params']);
        if (browseId.isNotEmpty && params.isNotEmpty) {
          final results = await ytmusic.getArtistAlbums(
            browseId,
            params,
            limit: 12,
          );
          singles.addAll(
            results.whereType<Map>().map(
              (item) => Map<String, dynamic>.from(item),
            ),
          );
        } else {
          singles.addAll(_asMapList(singlesSection['results']));
        }
      }

      final artistThumbnail = ytThumbnailUrl(artist);
      final songs = songResults
          .where((item) => readYtString(item['videoId']).isNotEmpty)
          .map(
            (item) => ytSongToTrack(
              item,
              fallbackArtistName: widget.artistName,
              fallbackArtistId: widget.channelId,
              fallbackThumbnailUrl: artistThumbnail,
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _artist = artist;
        _songs = songs;
        _albums = albums;
        _singles = singles;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load this artist.";
      });
    }
  }

  void _openAlbum(Map<String, dynamic> album) {
    final browseId = readYtString(album['browseId']);
    if (browseId.isEmpty) return;
    final title = readYtString(album['title'], 'Album');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumDetailsPage(
          albumId: browseId,
          albumTitle: title,
          artistId: widget.channelId,
          artistName: widget.artistName,
        ),
      ),
    );
  }

  Widget _buildReleaseRow(Map<String, dynamic> item) {
    final title = readYtString(item['title'], 'Album');
    final year = readYtString(item['year']);
    final thumbnailUrl = ytThumbnailUrl(item);
    final artists = item['artists'];
    final artistName = (artists is List && artists.isNotEmpty)
        ? readYtString((artists.first as Map?)?['name'], widget.artistName)
        : widget.artistName;
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openAlbum(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              NetworkThumbnail(
                url: thumbnailUrl,
                width: 54,
                height: 54,
                borderRadius: BorderRadius.circular(8),
                iconSize: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    Text(
                      [artistName, if (year.isNotEmpty) year].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final library = context.watch<LibraryProvider>();
    final downloads = context.watch<DownloadsProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final artist = _artist;
    final displayName = artist != null
        ? readYtString(artist['name'], widget.artistName)
        : widget.artistName;
    final subscribers = artist != null
        ? _labelCount(readYtString(artist['subscribers']), 'subscribers')
        : '';
    final views = artist != null
        ? _labelCount(readYtString(artist['views']), 'views')
        : '';
    final description = artist != null
        ? readYtString(artist['description'])
        : '';
    final thumbnailUrl = artist != null ? ytThumbnailUrl(artist) : '';
    final hasReleases =
        _songs.isNotEmpty || _albums.isNotEmpty || _singles.isNotEmpty;
    final isThisArtistPlaying =
        player.isPlaying &&
        player.currentTrack != null &&
        _songs.any((t) => t.id == player.currentTrack!.id);

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
                        children: [
                          InkWell(
                            onTap: () => Navigator.of(context).maybePop(),
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(
                                Icons.arrow_back_rounded,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 64),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: NetworkThumbnail(
                            url: thumbnailUrl,
                            fit: BoxFit.cover,
                            borderRadius: BorderRadius.circular(999),
                            iconSize: 40,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'ARTIST',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        displayName,
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.headlineMedium?.copyWith(fontSize: 26),
                      ),
                      if (subscribers.isNotEmpty || views.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 10,
                          runSpacing: 4,
                          children: [
                            if (subscribers.isNotEmpty)
                              Text(
                                subscribers,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            if (views.isNotEmpty)
                              Text(
                                views,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                          ],
                        ),
                      ],
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            description,
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                      if (!_loading && _error == null && _songs.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: player.toggleShuffle,
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
                              isPlaying: isThisArtistPlaying,
                              onTap: () => isThisArtistPlaying
                                  ? player.togglePlayPause()
                                  : player.shufflePlay(_songs),
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
                        const SizedBox(height: 16),
                        Consumer<SettingsProvider>(
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
                                final engine = selection.first;
                                settings.setSearchEngine(engine);
                                if (engine == SearchEngine.youtube) {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => YoutubeChannelPage(
                                        channelId: widget.channelId,
                                        channelName: widget.artistName,
                                      ),
                                    ),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _error != null
                    ? Padding(
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
                    : !hasReleases
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            'No music found for this artist.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_songs.isNotEmpty) ...[
                            _buildSectionTitle('Most streamed songs'),
                            ...List.generate(
                              _songs.length < displaySongsLimit
                                  ? _songs.length
                                  : displaySongsLimit,
                              (i) {
                                final track = _songs[i];
                                return TrackTile(
                                  index: i + 1,
                                  track: track,
                                  isActive: player.currentTrack?.id == track.id,
                                  onTap: () =>
                                      player.playQueue(_songs, startIndex: i),
                                  onPlayNext: () => player.playNext(track),
                                  onAddToQueue: () =>
                                      player.addToQueue(track),
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
                                );
                              },
                            ),
                          ],
                          if (_albums.isNotEmpty) ...[
                            _buildSectionTitle('Albums'),
                            ..._albums.map(_buildReleaseRow),
                          ],
                          if (_singles.isNotEmpty) ...[
                            _buildSectionTitle('Singles'),
                            ..._singles.map(_buildReleaseRow),
                          ],
                        ],
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
  final bool isPlaying;
  const _PlayButton({required this.onTap, this.isPlaying = false});

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
            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
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
