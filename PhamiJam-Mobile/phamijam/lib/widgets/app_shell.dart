import 'package:flutter/material.dart';
import 'package:phamijam/models/playlist.dart';
import 'package:phamijam/pages/home.dart';
import 'package:phamijam/pages/library_page.dart';
import 'package:phamijam/pages/playlist_detail_page.dart';
import 'package:phamijam/pages/search_page.dart';
import 'package:phamijam/pages/settings_page.dart';
import 'package:phamijam/providers/library_provider.dart';
import 'package:phamijam/widgets/bottom_nav_bar.dart';
import 'package:phamijam/widgets/mini_player.dart';
import 'package:provider/provider.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _navIndex = 0;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LibraryProvider>().refresh();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
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
          const MiniPlayer(),
          AppBottomNavBar(currentIndex: _navIndex, onTap: _handleNavTap),
        ],
      ),
    );
  }
}
