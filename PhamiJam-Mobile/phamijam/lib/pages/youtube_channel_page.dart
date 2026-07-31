import 'package:flutter/material.dart';
import 'package:phamijam/components/add_to_playlist_sheet.dart';
import 'package:phamijam/components/download_action.dart';
import 'package:phamijam/components/like_action.dart';
import 'package:phamijam/models/channel.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/pages/artist_page.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:phamijam/services/youtube_service.dart';
import 'package:phamijam/widgets/mini_player.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:phamijam/widgets/swipe_back.dart';
import 'package:phamijam/widgets/track_tile.dart';
import 'package:provider/provider.dart';

String _formatCount(String raw) {
  final value = int.tryParse(raw);
  if (value == null) return raw;
  if (value >= 1000000) {
    final millions = value / 1000000;
    return '${millions.toStringAsFixed(millions.truncateToDouble() == millions ? 0 : 1)}M';
  }
  if (value >= 1000) {
    final thousands = value / 1000;
    return '${thousands.toStringAsFixed(thousands.truncateToDouble() == thousands ? 0 : 1)}K';
  }
  return '$value';
}

class YoutubeChannelPage extends StatefulWidget {
  final String channelId;
  final String channelName;

  const YoutubeChannelPage({
    super.key,
    required this.channelId,
    required this.channelName,
  });

  @override
  State<YoutubeChannelPage> createState() => _YoutubeChannelPageState();
}

class _YoutubeChannelPageState extends State<YoutubeChannelPage> {
  Channel? _channel;
  List<Track> _videos = const [];
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
      final results = await Future.wait([
        YoutubeService.fetchChannelInfo(widget.channelId),
        YoutubeService.fetchChannelVideos(widget.channelId, maxItems: 25),
      ]);
      if (!mounted) return;
      setState(() {
        _channel = results[0] as Channel?;
        _videos = results[1] as List<Track>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load this channel.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final library = context.watch<LibraryProvider>();
    final downloads = context.watch<DownloadsProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final channel = _channel;
    final displayName = channel?.name ?? widget.channelName;
    final subscribers = (channel?.subscriberCount ?? '').isEmpty
        ? ''
        : '${_formatCount(channel!.subscriberCount)} subscribers';
    final description = channel?.description ?? '';

    return SwipeBack(
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
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
                            url: channel?.thumbnailUrl ?? '',
                            fit: BoxFit.cover,
                            borderRadius: BorderRadius.circular(999),
                            iconSize: 40,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'CHANNEL',
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
                      if (subscribers.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          subscribers,
                          style: Theme.of(context).textTheme.bodyMedium,
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
                      if (!_loading &&
                          _error == null &&
                          _videos.isNotEmpty) ...[
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
                              onTap: () => player.shuffle
                                  ? player.shufflePlay(_videos)
                                  : player.playQueue(_videos),
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
                                if (engine == SearchEngine.youtubeMusic) {
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) => ArtistPage(
                                        channelId: widget.channelId,
                                        artistName: widget.channelName,
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
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 24,
                  ),
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
                ),
              )
            else if (_videos.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      'No videos found for this channel.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final track = _videos[i];
                    return TrackTile(
                      index: i + 1,
                      track: track,
                      isActive: player.currentTrack?.id == track.id,
                      onTap: () => player.playQueue(_videos, startIndex: i),
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
                  }, childCount: _videos.length),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _PlayButton({required this.onTap});

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
            Icons.play_arrow_rounded,
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
