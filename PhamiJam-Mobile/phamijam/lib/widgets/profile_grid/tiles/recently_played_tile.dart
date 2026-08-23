import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/services/listening_history_service.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:provider/provider.dart';

class RecentlyPlayedTile extends StatelessWidget {
  const RecentlyPlayedTile({super.key, required this.profileUid});

  final String profileUid;

  bool get _isOwner => profileUid == FirebaseAuth.instance.currentUser?.uid;

  static Future<List<Track>> _fetchFor(String uid) async {
    final since = DateTime.now().subtract(const Duration(days: 180));
    final events = await ListeningHistoryService.eventsSinceForUid(
      uid,
      since,
    );
    final seen = <String>{};
    final tracks = <Track>[];
    for (final event in events.reversed) {
      if (!seen.add(event.videoId)) continue;
      tracks.add(
        Track(
          id: 'yt-${event.videoId}',
          title: event.title,
          artist: event.artist,
          thumbnailUrl: event.thumbnailUrl,
          videoId: event.videoId,
          channelId: event.channelId,
        ),
      );
      if (tracks.length >= 5) break;
    }
    return tracks;
  }

  @override
  Widget build(BuildContext context) {
    if (_isOwner) {
      final tracks = context.watch<LibraryProvider>().recentlyPlayed;
      return _RecentlyPlayedList(tracks: tracks.take(5).toList());
    }
    return FutureBuilder<List<Track>>(
      future: _fetchFor(profileUid),
      builder: (context, snapshot) {
        return _RecentlyPlayedList(tracks: snapshot.data ?? const []);
      },
    );
  }
}

class _RecentlyPlayedList extends StatelessWidget {
  const _RecentlyPlayedList({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (tracks.isEmpty) {
      return Center(
        child: Text(
          'Nothing played yet',
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recently played',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.separated(
              itemCount: tracks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final track = tracks[index];
                return Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: NetworkThumbnail(
                          url: track.thumbnailUrl,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
