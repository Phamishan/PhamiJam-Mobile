import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/services/liked_songs_service.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';

class LikedSongsTile extends StatelessWidget {
  const LikedSongsTile({super.key, required this.profileUid});

  final String profileUid;

  bool get _isOwner => profileUid == FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (!_isOwner) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Liked songs are private',
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
      );
    }

    return FutureBuilder<List<Track>>(
      future: LikedSongsService.fetchAll(),
      builder: (context, snapshot) {
        final songs = snapshot.data ?? const [];
        if (snapshot.connectionState == ConnectionState.done && songs.isEmpty) {
          return Center(
            child: Text(
              'No liked songs yet',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Liked songs',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.separated(
                  itemCount: songs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: NetworkThumbnail(
                              url: song.thumbnailUrl,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            song.title,
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
      },
    );
  }
}
