import 'package:flutter/material.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:phamijam/widgets/section_header.dart';
import 'package:provider/provider.dart';

class QuickAccessRow extends StatelessWidget {
  const QuickAccessRow({super.key, required this.onOpenPlaylist});

  final ValueChanged<Playlist> onOpenPlaylist;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final settings = context.watch<SettingsProvider>();

    final byId = {
      for (final p in [...library.userPlaylists, ...library.mixedPlaylists])
        if (!settings.isPlaylistHidden(p.id)) p.id: p,
    };
    final pinned = [
      for (final id in library.pinnedPlaylistIds)
        if (byId[id] != null) byId[id]!,
    ];
    if (pinned.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: 'Quick access'),
        SizedBox(
          height: 156,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: pinned.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final playlist = pinned[index];
              return _QuickCard(
                title: playlist.title,
                onTap: () => onOpenPlaylist(playlist),
                cover: NetworkThumbnail(
                  url: playlist.coverImageUrl,
                  width: 108,
                  height: 108,
                  iconSize: 32,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.title,
    required this.cover,
    required this.onTap,
  });

  final String title;
  final Widget cover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 108,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(width: 108, height: 108, child: cover),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
