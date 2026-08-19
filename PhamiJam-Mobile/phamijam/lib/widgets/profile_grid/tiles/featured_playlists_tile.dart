import 'package:flutter/material.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/services/profile_service.dart';
import 'package:phamijam/services/youtube_service.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';

class FeaturedPlaylistsTile extends StatelessWidget {
  const FeaturedPlaylistsTile({super.key, required this.profileUid});

  final String profileUid;

  static Future<List<Playlist>> _fetchPublicFeatured(String uid) async {
    final ids = await ProfileService.fetchProfilePlaylistIds(uid);
    final playlists = await Future.wait(
      ids.map((id) async {
        try {
          return await YoutubeService.fetchPlaylistById(id);
        } catch (_) {
          return null;
        }
      }),
    );
    return playlists.whereType<Playlist>().where((p) => !p.isPrivate).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Playlist>>(
      future: _fetchPublicFeatured(profileUid),
      builder: (context, snapshot) {
        final playlists = snapshot.data ?? const [];
        final colorScheme = Theme.of(context).colorScheme;

        if (snapshot.connectionState == ConnectionState.done &&
            playlists.isEmpty) {
          return Center(
            child: Text(
              'No public playlists yet',
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
                'Playlists',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: playlists.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    return SizedBox(
                      width: 64,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: NetworkThumbnail(
                          url: playlist.thumbnailUrl,
                          fit: BoxFit.cover,
                        ),
                      ),
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
