import 'package:flutter/material.dart';
import 'package:phamijam/models/channel.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/pages/artist_page.dart';
import 'package:phamijam/services/youtube_service.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';

class _RecentArtist {
  final String channelId;
  final String name;

  const _RecentArtist({required this.channelId, required this.name});
}

List<_RecentArtist> _distinctArtists(List<Track> tracks, int max) {
  final seen = <String>{};
  final artists = <_RecentArtist>[];
  for (final track in tracks) {
    final channelId = track.channelId;
    if (channelId == null || channelId.isEmpty) continue;
    if (!seen.add(channelId)) continue;
    artists.add(_RecentArtist(channelId: channelId, name: track.artist));
    if (artists.length >= max) break;
  }
  return artists;
}

class RecentArtistsRow extends StatefulWidget {
  final List<Track> tracks;
  final int maxArtists;

  const RecentArtistsRow({
    super.key,
    required this.tracks,
    this.maxArtists = 5,
  });

  @override
  State<RecentArtistsRow> createState() => _RecentArtistsRowState();
}

class _RecentArtistsRowState extends State<RecentArtistsRow> {
  late List<_RecentArtist> _artists;
  Map<String, Channel> _channels = {};

  @override
  void initState() {
    super.initState();
    _artists = _distinctArtists(widget.tracks, widget.maxArtists);
    _loadChannels();
  }

  @override
  void didUpdateWidget(covariant RecentArtistsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tracks == widget.tracks) return;
    final artists = _distinctArtists(widget.tracks, widget.maxArtists);
    if (artists.map((a) => a.channelId).join() ==
        _artists.map((a) => a.channelId).join()) {
      return;
    }
    setState(() => _artists = artists);
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    if (_artists.isEmpty) return;
    try {
      final channels = await YoutubeService.fetchChannelsInfo(
        _artists.map((a) => a.channelId).toList(),
      );
      if (!mounted) return;
      setState(() => _channels = channels);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_artists.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _artists.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final artist = _artists[index];
          final channel = _channels[artist.channelId];
          final onTap = openArtistPageCallback(
            context,
            channelId: artist.channelId,
            artistName: artist.name,
          );
          return SizedBox(
            width: 76,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(999),
              child: Column(
                children: [
                  NetworkThumbnail(
                    url: channel?.thumbnailUrl ?? '',
                    width: 68,
                    height: 68,
                    borderRadius: BorderRadius.circular(999),
                    iconSize: 26,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    channel?.name ?? artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
