import 'package:flutter/material.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:phamijam/widgets/swipe_back.dart';
import 'package:provider/provider.dart';

class ManagePlaylistVisibilityPage extends StatelessWidget {
  const ManagePlaylistVisibilityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final library = context.watch<LibraryProvider>();
    final settings = context.watch<SettingsProvider>();
    final playlists = library.userPlaylists;

    return SwipeBack(
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
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
                    const SizedBox(width: 4),
                    Text(
                      'Playlist Visibility',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4),
                  child: Text(
                    'Uncheck a playlist to hide it from Home and Library.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: playlists.isEmpty
                      ? Center(
                          child: Text(
                            "You don't have any playlists yet.",
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 16),
                          children: [
                            for (final playlist in playlists)
                              CheckboxListTile(
                                secondary: NetworkThumbnail(
                                  url: playlist.thumbnailUrl,
                                  width: 44,
                                  height: 44,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                title: Text(
                                  playlist.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                value: !settings.isPlaylistHidden(playlist.id),
                                onChanged: (checked) => settings
                                    .setPlaylistHidden(
                                      playlist.id,
                                      !(checked ?? true),
                                    ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
