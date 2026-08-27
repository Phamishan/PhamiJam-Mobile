import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/pages/friend_profile_page.dart';
import 'package:phamijam/pages/home.dart';
import 'package:phamijam/pages/library_page.dart';
import 'package:phamijam/pages/now_playing_page.dart';
import 'package:phamijam/pages/playlist_detail_page.dart';
import 'package:phamijam/pages/profile_page.dart';
import 'package:phamijam/pages/search_page.dart';
import 'package:phamijam/providers/edited_songs_provider.dart';
import 'package:phamijam/providers/friends_provider.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/providers/profile_provider.dart';
import 'package:phamijam/providers/saved_playlists_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/providers/theme_provider.dart';
import 'package:phamijam/services/deep_link_service.dart';
import 'package:phamijam/services/jamstats_widget_service.dart';
import 'package:phamijam/services/profile_service.dart';
import 'package:phamijam/services/youtube_service.dart';
import 'package:phamijam/widgets/bottom_nav_bar.dart';
import 'package:phamijam/widgets/mini_player.dart';
import 'package:phamijam/widgets/remote_session_banner.dart';
import 'package:provider/provider.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _navIndex = 0;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _showingSkipSuggestion = false;
  late final PlayerProvider _player;
  String? _lastPushedNowPlayingVideoId;
  bool? _lastPushedNowPlayingIsPlaying;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LibraryProvider>().refresh(silentOnly: true);
    });
    _player = context.read<PlayerProvider>();
    _player.bindEditedSongsLookup(context.read<EditedSongsProvider>().trimFor);
    _player.bindAutoplayEnabled(
      () => context.read<SettingsProvider>().autoplayEnabled,
    );
    unawaited(context.read<EditedSongsProvider>().refresh());
    unawaited(context.read<SavedPlaylistsProvider>().refresh());
    unawaited(context.read<ProfileProvider>().refresh());
    context.read<FriendsProvider>().start();
    unawaited(context.read<SettingsProvider>().refreshHiddenPlaylists());
    _player.addListener(_handlePlayerChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshWidgets());
    unawaited(DeepLinkService.init(_handleDeepLink));
  }

  Future<void> _handleDeepLink(DeepLinkTarget target) async {
    if (!mounted) return;
    if (target.type == DeepLinkType.song) {
      try {
        final track = await YoutubeService.fetchVideoById(target.id);
        if (track == null || !mounted) return;
        await _player.playQueue([track]);
        if (!mounted) return;
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const NowPlayingPage()));
      } catch (error) {
        if (mounted) {
          AppFlushbar.error(context, "Couldn't open shared song.");
        }
      }
      return;
    }

    if (target.type == DeepLinkType.profile) {
      final resolvedUid = await ProfileService.resolveProfileLinkId(target.id);
      if (!mounted) return;
      final ownUid = FirebaseAuth.instance.currentUser?.uid;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => resolvedUid == ownUid
              ? const ProfilePage()
              : FriendProfilePage(uid: resolvedUid),
        ),
      );
      return;
    }

    try {
      final playlist = await YoutubeService.fetchPlaylistById(target.id);
      if (playlist == null || !mounted) return;
      _openPlaylist(context, playlist);
    } catch (error) {
      if (mounted) {
        AppFlushbar.error(context, "Couldn't open shared playlist.");
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.removeListener(_handlePlayerChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    context.read<FriendsProvider>().stop();
    super.dispose();
  }

  Future<void> _refreshWidgets() {
    final accentColor = context.read<ThemeProvider>().accentColor?.toARGB32();
    return JamstatsWidgetService.refresh(accentColor: accentColor);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.paused) {
      unawaited(_refreshWidgets());
    }
  }

  void _handlePlayerChanged() {
    _maybePushNowPlaying();

    final playbackError = _player.playbackErrorMessage;
    if (playbackError != null) {
      _player.consumePlaybackError();
      AppFlushbar.error(context, playbackError);
    }

    final track = _player.suggestedRemovalTrack;
    final playlist = _player.suggestedRemovalPlaylist;
    if (track == null || playlist == null || _showingSkipSuggestion) return;
    if (!context.read<SettingsProvider>().suggestRemovingSkippedSongs) {
      _player.dismissSkipSuggestion();
      return;
    }
    _showingSkipSuggestion = true;
    _showSkipSuggestionDialog(track, playlist).whenComplete(() {
      _showingSkipSuggestion = false;
    });
  }

  void _maybePushNowPlaying() {
    final track = _player.currentTrack;
    final isPlaying = _player.isPlaying;
    if (track?.videoId == _lastPushedNowPlayingVideoId &&
        isPlaying == _lastPushedNowPlayingIsPlaying) {
      return;
    }
    _lastPushedNowPlayingVideoId = track?.videoId;
    _lastPushedNowPlayingIsPlaying = isPlaying;
    unawaited(
      JamstatsWidgetService.pushNowPlaying(track: track, isPlaying: isPlaying),
    );
  }

  Future<void> _showSkipSuggestionDialog(Track track, Playlist playlist) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Skipping this a lot?'),
        content: Text(
          'You\'ve skipped "${track.title}" early several times in '
          '"${playlist.title}". Remove it from the playlist?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    await _player.dismissSkipSuggestion();
    if (remove != true || !mounted) return;

    final library = context.read<LibraryProvider>();
    try {
      if (playlist.isFromYoutube) {
        await library.removeTrackFromPlaylist(playlist, track);
      } else {
        await library.toggleLike(track);
      }
      if (mounted) AppFlushbar.success(context, 'Removed "${track.title}"');
    } catch (error) {
      if (mounted) {
        AppFlushbar.error(context, "Couldn't remove track: $error");
      }
    }
  }

  void _openPlaylist(BuildContext context, Playlist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailPage(
          playlist: playlist,
          onBack: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _enterSearch() {
    setState(() => _navIndex = 1);
  }

  void _exitSearch() {
    setState(() {
      _searchQuery = '';
      _navIndex = 0;
    });
    _searchController.clear();
    _searchFocusNode.unfocus();
  }

  void _handleNavTap(int index) {
    if (index == 1) {
      _enterSearch();
      return;
    }
    _searchFocusNode.unfocus();
    setState(() => _navIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _navIndex,
              children: [
                HomePage(
                  onOpenPlaylist: (p) => _openPlaylist(context, p),
                  onOpenSearch: _enterSearch,
                  onOpenLibrary: () => _handleNavTap(2),
                ),
                SearchPage(
                  query: _searchQuery,
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onQueryChanged: (value) =>
                      setState(() => _searchQuery = value),
                  onClose: _exitSearch,
                  onOpenPlaylist: (p) => _openPlaylist(context, p),
                ),
                LibraryPage(onOpenPlaylist: (p) => _openPlaylist(context, p)),
                const ProfilePage(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const RemoteSessionBanner(),
          const MiniPlayer(),
          AppBottomNavBar(currentIndex: _navIndex, onTap: _handleNavTap),
        ],
      ),
    );
  }
}
