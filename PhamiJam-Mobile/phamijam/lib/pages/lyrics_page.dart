import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/services/lyrics_service.dart';
import 'package:phamijam/widgets/network_thumbnail.dart';
import 'package:provider/provider.dart';

class LyricsPage extends StatefulWidget {
  const LyricsPage({super.key});

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  late final PlayerProvider _player;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};

  String? _videoId;
  SongLyrics? _lyrics;
  bool _loading = true;
  String? _error;
  int _syncOffsetMs = 0;
  int _lastActiveIndex = -1;
  bool _userScrolling = false;
  Timer? _resumeAutoScrollTimer;

  @override
  void initState() {
    super.initState();
    _player = context.read<PlayerProvider>();
    _player.addListener(_handlePlayerChanged);
    _load();
  }

  @override
  void dispose() {
    _player.removeListener(_handlePlayerChanged);
    _resumeAutoScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _resumeAutoScrollTimer?.cancel();
      _userScrolling = true;
    } else if (notification is ScrollEndNotification) {
      _resumeAutoScrollTimer?.cancel();
      _resumeAutoScrollTimer = Timer(const Duration(seconds: 4), () {
        _userScrolling = false;
      });
    }
    return false;
  }

  void _handlePlayerChanged() {
    final videoId = _player.currentTrack?.videoId;
    if (videoId != _videoId) {
      _load();
      return;
    }
    _maybeAutoScroll();
  }

  Future<void> _load() async {
    final videoId = _player.currentTrack?.videoId;
    _videoId = videoId;
    _lineKeys.clear();
    setState(() {
      _loading = true;
      _error = null;
      _lyrics = null;
      _lastActiveIndex = -1;
    });

    if (videoId == null) {
      setState(() {
        _loading = false;
        _error = "This track can't show lyrics.";
      });
      return;
    }

    try {
      final track = _player.currentTrack;
      final lyrics = await LyricsService.fetchFor(
        videoId,
        title: track?.title,
        artist: track?.artist,
        durationSeconds: (track != null && track.duration > Duration.zero)
            ? track.duration.inSeconds
            : null,
      );
      final offset = await LyricsService.getSyncOffsetMs(videoId);
      if (!mounted || _player.currentTrack?.videoId != videoId) return;
      setState(() {
        _lyrics = lyrics;
        _syncOffsetMs = offset;
        _loading = false;
        _error = (lyrics == null || !lyrics.hasAny)
            ? 'No lyrics found for this song.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load lyrics.";
      });
    }
  }

  Duration get _effectivePosition =>
      _player.position + Duration(milliseconds: _syncOffsetMs);

  int _activeLineIndex() {
    final synced = _lyrics?.synced;
    if (synced == null || synced.isEmpty) return -1;
    final position = _effectivePosition;
    for (var i = synced.length - 1; i >= 0; i--) {
      if (position >= synced[i].start) return i;
    }
    return -1;
  }

  void _maybeAutoScroll() {
    final synced = _lyrics?.synced;
    if (synced == null || synced.isEmpty) return;
    final index = _activeLineIndex();
    if (index < 0 || index == _lastActiveIndex) return;
    _lastActiveIndex = index;
    if (!mounted) return;
    setState(() {});
    if (_userScrolling) return;
    final lineContext = _lineKeys[index]?.currentContext;
    if (lineContext == null) return;
    Scrollable.ensureVisible(
      lineContext,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: 0.4,
    );
  }

  Future<void> _adjustOffset(int deltaMs) async {
    final videoId = _videoId;
    if (videoId == null) return;
    final next = _syncOffsetMs + deltaMs;
    setState(() => _syncOffsetMs = next);
    await LyricsService.setSyncOffsetMs(videoId, next);
  }

  void _seekToLine(LyricLine line) {
    final target = line.start - Duration(milliseconds: _syncOffsetMs);
    _player.seek(target < Duration.zero ? Duration.zero : target);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final track = _player.currentTrack;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(track?.title ?? 'Lyrics', overflow: TextOverflow.ellipsis),
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primary.withValues(alpha: 0.25),
              colorScheme.surface,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          top: false,
          child: track == null
              ? Center(
                  child: Text(
                    'Nothing playing',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: NetworkThumbnail(
                                url: track.thumbnailUrl,
                                fit: BoxFit.cover,
                                iconSize: 20,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                if ((_lyrics?.source ?? '').isNotEmpty)
                                  Text(
                                    'Lyrics via ${_lyrics!.source}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color:
                                              colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: _buildBody(context)),
                    if (_lyrics?.hasSynced == true) _buildSyncControls(context),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lyrics_outlined,
                size: 44,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    final lyrics = _lyrics;
    if (lyrics == null || !lyrics.hasAny) {
      return const SizedBox.shrink();
    }

    if (lyrics.hasSynced) {
      final synced = lyrics.synced!;
      final activeIndex = _activeLineIndex();
      return NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          itemCount: synced.length,
          itemBuilder: (context, i) {
            final key = _lineKeys.putIfAbsent(i, () => GlobalKey());
            final isActive = i == activeIndex;
            return Padding(
              key: key,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: GestureDetector(
                onTap: () => _seekToLine(synced[i]),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style:
                      Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: isActive
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: isActive
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.6,
                              ),
                      ) ??
                      const TextStyle(),
                  child: Text(synced[i].text),
                ),
              ),
            );
          },
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Text(
        lyrics.plainText ?? '',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }

  Widget _buildSyncControls(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final seconds = (_syncOffsetMs / 1000).toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () => _adjustOffset(-250),
            icon: const Icon(Icons.remove_rounded),
          ),
          Text(
            _syncOffsetMs == 0
                ? 'Synced'
                : '${_syncOffsetMs > 0 ? '+' : ''}${seconds}s',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          IconButton(
            onPressed: () => _adjustOffset(250),
            icon: const Icon(Icons.add_rounded),
          ),
          if (_syncOffsetMs != 0)
            TextButton(
              onPressed: () => _adjustOffset(-_syncOffsetMs),
              child: const Text('Reset'),
            ),
        ],
      ),
    );
  }
}
