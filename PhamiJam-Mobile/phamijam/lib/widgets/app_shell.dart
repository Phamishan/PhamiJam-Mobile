import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/models/track.dart';
import 'package:phamijam/pages/home.dart';
import 'package:phamijam/pages/library_page.dart';
import 'package:phamijam/pages/playlist_detail_page.dart';
import 'package:phamijam/pages/search_page.dart';
import 'package:phamijam/pages/settings_page.dart';
import 'package:phamijam/providers/edited_songs_provider.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/providers/player_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/services/wrapphamied_widget_service.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LibraryProvider>().refresh();
    });
    _player = context.read<PlayerProvider>();
    _player.bindEditedSongsLookup(context.read<EditedSongsProvider>().trimFor);
    unawaited(context.read<EditedSongsProvider>().refresh());
    _player.addListener(_handlePlayerChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(WrapphamiedWidgetService.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.removeListener(_handlePlayerChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(WrapphamiedWidgetService.refresh());
    }
  }

  void _handlePlayerChanged() {
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
                const SettingsPage(),
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
