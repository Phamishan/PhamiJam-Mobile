import 'package:flutter/material.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/pages/playlist_detail_page.dart';
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
                  itemCount: playlists.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlaylistDetailPage(
                              playlist: playlist,
                              onBack: () => Navigator.of(context).pop(),
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: NetworkThumbnail(
                                    url: playlist.thumbnailUrl,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  playlist.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
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
