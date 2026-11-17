import 'package:flutter/foundation.dart';
import 'package:phamijam/services/hidden_playlists_service.dart';
import 'package:phamijam/services/log_service.dart';
import 'package:phamijam/services/profile_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _miniPlayerSwipeToDismissKey =
    'phamijam.mini_player_swipe_to_dismiss';
const String _suggestRemovingSkippedSongsKey =
    'phamijam.suggest_removing_skipped_songs';
const String _searchEngineKey = 'phamijam.search_engine';
const String _hiddenPlaylistIdsKey = 'phamijam.hidden_playlist_ids';
const String _autoplayEnabledKey = 'phamijam.autoplay_enabled';
const String _crossfadeEnabledKey = 'phamijam.crossfade_enabled';
const String _crossfadeDurationMsKey = 'phamijam.crossfade_duration_ms';
const String _showActivityEnabledKey = 'phamijam.show_activity_enabled';

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
  bool _crossfadeEnabled = false;
  int _crossfadeDurationMs = 4000;
  bool _showActivityEnabled = true;

  bool get miniPlayerSwipeToDismiss => _miniPlayerSwipeToDismiss;
  bool get suggestRemovingSkippedSongs => _suggestRemovingSkippedSongs;
  SearchEngine get searchEngine => _searchEngine;
  bool get autoplayEnabled => _autoplayEnabled;
  bool get crossfadeEnabled => _crossfadeEnabled;
  bool get showActivityEnabled => _showActivityEnabled;
  int get crossfadeDurationMs => _crossfadeDurationMs;
  Duration get crossfadeDuration =>
      Duration(milliseconds: _crossfadeDurationMs);
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
    final savedCrossfade = prefs.getBool(_crossfadeEnabledKey);
    if (savedCrossfade != null) {
      _crossfadeEnabled = savedCrossfade;
    }
    final savedCrossfadeDurationMs = prefs.getInt(_crossfadeDurationMsKey);
    if (savedCrossfadeDurationMs != null) {
      _crossfadeDurationMs = savedCrossfadeDurationMs.clamp(1000, 12000);
    }
    final savedShowActivity = prefs.getBool(_showActivityEnabledKey);
    if (savedShowActivity != null) {
      _showActivityEnabled = savedShowActivity;
    }
    notifyListeners();
  }

  Future<void> setMiniPlayerSwipeToDismiss(bool value) async {
    if (value == _miniPlayerSwipeToDismiss) return;
    Log.i('settings', 'mini player swipe to dismiss -> $value');
    _miniPlayerSwipeToDismiss = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_miniPlayerSwipeToDismissKey, value);
  }

  Future<void> setSuggestRemovingSkippedSongs(bool value) async {
    if (value == _suggestRemovingSkippedSongs) return;
    Log.i('settings', 'suggest removing skipped songs -> $value');
    _suggestRemovingSkippedSongs = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_suggestRemovingSkippedSongsKey, value);
  }

  Future<void> setSearchEngine(SearchEngine value) async {
    if (value == _searchEngine) return;
    Log.i('settings', 'search engine -> ${value.name}');
    _searchEngine = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_searchEngineKey, value.name);
  }

  Future<void> setAutoplayEnabled(bool value) async {
    if (value == _autoplayEnabled) return;
    Log.i('settings', 'autoplay -> $value');
    _autoplayEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoplayEnabledKey, value);
  }

  Future<void> setCrossfadeEnabled(bool value) async {
    if (value == _crossfadeEnabled) return;
    Log.i('settings', 'crossfade -> $value');
    _crossfadeEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_crossfadeEnabledKey, value);
  }

  Future<void> setCrossfadeDurationMs(int value) async {
    final clamped = value.clamp(1000, 12000);
    if (clamped == _crossfadeDurationMs) return;
    Log.i('settings', 'crossfade duration -> $clamped ms');
    _crossfadeDurationMs = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_crossfadeDurationMsKey, clamped);
  }

  Future<void> refreshShowActivityEnabled() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final profile = await ProfileService.fetchProfile(uid);
      _showActivityEnabled = profile.showActivityEnabled;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_showActivityEnabledKey, _showActivityEnabled);
    } catch (error) {
      Log.e('settings', 'could not read show-activity setting', error);
    }
  }

  Future<void> setShowActivityEnabled(bool value) async {
    if (value == _showActivityEnabled) return;
    Log.i('settings', 'show activity -> $value');
    final previous = _showActivityEnabled;
    _showActivityEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showActivityEnabledKey, value);
    try {
      await ProfileService.setShowActivity(value);
    } catch (error) {
      Log.e('settings', 'saving show-activity failed, reverting', error);
      _showActivityEnabled = previous;
      notifyListeners();
      await prefs.setBool(_showActivityEnabledKey, previous);
      rethrow;
    }
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
      Log.e('settings', 'refreshing hidden playlists failed', error);
    }
  }

  Future<void> setPlaylistHidden(String playlistId, bool hidden) async {
    final isHidden = _hiddenPlaylistIds.contains(playlistId);
    if (hidden == isHidden) return;
    Log.i('settings', '${hidden ? 'hiding' : 'showing'} playlist $playlistId');
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
      Log.e('settings', 'saving playlist visibility failed, reverting', error);
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
