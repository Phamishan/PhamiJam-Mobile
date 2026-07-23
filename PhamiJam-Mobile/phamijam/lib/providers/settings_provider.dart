import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _miniPlayerSwipeToDismissKey =
    'phamijam.mini_player_swipe_to_dismiss';
const String _suggestRemovingSkippedSongsKey =
    'phamijam.suggest_removing_skipped_songs';

class SettingsProvider extends ChangeNotifier {
  bool _miniPlayerSwipeToDismiss = false;
  bool _suggestRemovingSkippedSongs = true;

  bool get miniPlayerSwipeToDismiss => _miniPlayerSwipeToDismiss;
  bool get suggestRemovingSkippedSongs => _suggestRemovingSkippedSongs;

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
}
