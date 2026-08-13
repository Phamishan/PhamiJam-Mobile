import 'package:flutter/foundation.dart';
import 'package:phamijam/services/hidden_playlists_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _miniPlayerSwipeToDismissKey =
    'phamijam.mini_player_swipe_to_dismiss';
const String _suggestRemovingSkippedSongsKey =
    'phamijam.suggest_removing_skipped_songs';
const String _searchEngineKey = 'phamijam.search_engine';
const String _hiddenPlaylistIdsKey = 'phamijam.hidden_playlist_ids';
const String _autoplayEnabledKey = 'phamijam.autoplay_enabled';

enum SearchEngine {
  youtubeMusic,
  youtube;

  static SearchEngine fromName(String? name) => SearchEngine.values.firstWhere(
    (e) => e.name == name,
    orElse: () => youtubeMusic,
  );
}

class SettingsProvider extends ChangeNotifier {
  bool _miniPlayerSwipeToDismiss = false;
  bool _suggestRemovingSkippedSongs = true;
  SearchEngine _searchEngine = SearchEngine.youtubeMusic;
  Set<String> _hiddenPlaylistIds = {};
  bool _autoplayEnabled = false;

  bool get miniPlayerSwipeToDismiss => _miniPlayerSwipeToDismiss;
  bool get suggestRemovingSkippedSongs => _suggestRemovingSkippedSongs;
  SearchEngine get searchEngine => _searchEngine;
  bool get autoplayEnabled => _autoplayEnabled;
  bool isPlaylistHidden(String playlistId) =>
      _hiddenPlaylistIds.contains(playlistId);

  SettingsProvider() {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_miniPlayerSwipeToDismissKey);
    if (saved != null && saved != _miniPlayerSwipeToDismiss) {
      _miniPlayerSwipeToDismiss = saved;
    }
    final savedSuggest = prefs.getBool(_suggestRemovingSkippedSongsKey);
    if (savedSuggest != null && savedSuggest != _suggestRemovingSkippedSongs) {
      _suggestRemovingSkippedSongs = savedSuggest;
    }
    _searchEngine = SearchEngine.fromName(prefs.getString(_searchEngineKey));
    final savedHiddenPlaylistIds = prefs.getStringList(_hiddenPlaylistIdsKey);
    if (savedHiddenPlaylistIds != null) {
      _hiddenPlaylistIds = savedHiddenPlaylistIds.toSet();
    }
    final savedAutoplay = prefs.getBool(_autoplayEnabledKey);
    if (savedAutoplay != null) {
      _autoplayEnabled = savedAutoplay;
    }
    notifyListeners();
  }

  Future<void> setMiniPlayerSwipeToDismiss(bool value) async {
    if (value == _miniPlayerSwipeToDismiss) return;
    _miniPlayerSwipeToDismiss = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_miniPlayerSwipeToDismissKey, value);
  }

  Future<void> setSuggestRemovingSkippedSongs(bool value) async {
    if (value == _suggestRemovingSkippedSongs) return;
    _suggestRemovingSkippedSongs = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_suggestRemovingSkippedSongsKey, value);
  }

  Future<void> setSearchEngine(SearchEngine value) async {
    if (value == _searchEngine) return;
    _searchEngine = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_searchEngineKey, value.name);
  }

  Future<void> setAutoplayEnabled(bool value) async {
    if (value == _autoplayEnabled) return;
    _autoplayEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoplayEnabledKey, value);
  }

  Future<void> refreshHiddenPlaylists() async {
    try {
      final remote = await HiddenPlaylistsService.fetchAll();
      _hiddenPlaylistIds = remote.toSet();
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _hiddenPlaylistIdsKey,
        _hiddenPlaylistIds.toList(),
      );
    } catch (error) {
      debugPrint('SettingsProvider: refreshHiddenPlaylists failed: $error');
    }
  }

  Future<void> setPlaylistHidden(String playlistId, bool hidden) async {
    final isHidden = _hiddenPlaylistIds.contains(playlistId);
    if (hidden == isHidden) return;
    _hiddenPlaylistIds = {..._hiddenPlaylistIds};
    if (hidden) {
      _hiddenPlaylistIds.add(playlistId);
    } else {
      _hiddenPlaylistIds.remove(playlistId);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _hiddenPlaylistIdsKey,
      _hiddenPlaylistIds.toList(),
    );

    try {
      if (hidden) {
        await HiddenPlaylistsService.hide(playlistId);
      } else {
        await HiddenPlaylistsService.unhide(playlistId);
      }
    } catch (error) {
      _hiddenPlaylistIds = {..._hiddenPlaylistIds};
      if (hidden) {
        _hiddenPlaylistIds.remove(playlistId);
      } else {
        _hiddenPlaylistIds.add(playlistId);
      }
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _hiddenPlaylistIdsKey,
        _hiddenPlaylistIds.toList(),
      );
      rethrow;
    }
  }
}
