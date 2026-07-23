import 'package:flutter/material.dart';
import 'package:phamijam/components/add_to_playlist_sheet.dart';
import 'package:phamijam/components/download_action.dart';
import 'package:phamijam/components/like_action.dart';
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
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

class AlbumDetailsPage extends StatefulWidget {
  final String albumId;
  final String albumTitle;
  final String artistId;
  final String artistName;

  const AlbumDetailsPage({
    super.key,
    required this.albumId,
    required this.albumTitle,
    required this.artistId,
    required this.artistName,
  });

  @override
  State<AlbumDetailsPage> createState() => _AlbumDetailsPageState();
}

class _AlbumDetailsPageState extends State<AlbumDetailsPage> {
  Map<String, dynamic>? _album;
  List<Track> _tracks = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ytmusic = await YTMusic.create();
      final album = Map<String, dynamic>.from(
        await ytmusic.getAlbum(widget.albumId),
      );
      final rawTracks = (album['tracks'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      final albumThumbnail = ytThumbnailUrl(album);
      final tracks = rawTracks
          .where((item) => readYtString(item['videoId']).isNotEmpty)
          .map(
            (item) => ytSongToTrack(
              item,
              fallbackArtistName: widget.artistName,
              fallbackArtistId: widget.artistId,
              fallbackThumbnailUrl: albumThumbnail,
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _album = album;
        _tracks = tracks;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load this album.";
      });
    }
  }

  List<MapEntry<String, String?>> _artistLinks(Map<String, dynamic>? album) {
    final entries = <MapEntry<String, String?>>[];
    final artists = album?['artists'];
    if (artists is List) {
      for (final artist in artists) {
        if (artist is Map) {
          final name = readYtString(artist['name']);
          if (name.isNotEmpty) {
            final id = readYtString(artist['id']);
            entries.add(MapEntry(name, id.isEmpty ? null : id));
          }
        }
      }
    }
    if (entries.isEmpty) {
      entries.add(MapEntry(widget.artistName, widget.artistId));
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final library = context.watch<LibraryProvider>();
    final downloads = context.watch<DownloadsProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final album = _album;
    final displayTitle = album != null
        ? readYtString(album['title'], widget.albumTitle)
        : widget.albumTitle;
    final thumbnailUrl = album != null ? ytThumbnailUrl(album) : '';
    final year = album != null ? readYtString(album['year']) : '';
    final description = album != null ? readYtString(album['description']) : '';
    final artistLinks = _artistLinks(album);

    return SwipeBack(
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NetworkThumbnail(
                      url: thumbnailUrl,
                      width: 96,
                      height: 96,
                      borderRadius: BorderRadius.circular(12),
                      iconSize: 32,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayTitle,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              for (final entry in artistLinks)
                                if (entry.value != null)
                                  GestureDetector(
                                    onTap: openArtistPageCallback(
                                      context,
                                      channelId: entry.value,
                                      artistName: entry.key,
                                    ),
                                    child: Text(
                                      entry.key,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                    ),
                                  )
                                else
                                  Text(
                                    entry.key,
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                              if (year.isNotEmpty)
                                Text(
                                  year,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                            ],
                          ),
                          if (description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              description,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
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
                else if (_tracks.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'No playable tracks were found for this album.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  )
                else ...[
                  Text(
                    'Songs (${_tracks.length})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(_tracks.length, (i) {
                    final track = _tracks[i];
                    return TrackTile(
                      index: i + 1,
                      track: track,
                      isActive: player.currentTrack?.id == track.id,
                      onTap: () => player.playQueue(_tracks, startIndex: i),
                      onPlayNext: () => player.playNext(track),
                      onMore: () => showAddToPlaylistSheet(context, track),
                      isLiked: library.isLiked(track),
                      onToggleLike: () => toggleTrackLike(context, track),
                      isDownloaded: downloads.isDownloaded(track.videoId),
                      downloadProgress: downloads.progressFor(track.videoId),
                      onToggleDownload: () =>
                          toggleTrackDownload(context, track),
                      onCancelDownload: track.videoId == null
                          ? null
                          : () => downloads.cancelDownload(track.videoId!),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
