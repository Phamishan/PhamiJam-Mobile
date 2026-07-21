import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _miniPlayerSwipeToDismissKey =
    'phamijam.mini_player_swipe_to_dismiss';

class SettingsProvider extends ChangeNotifier {
  bool _miniPlayerSwipeToDismiss = false;

  bool get miniPlayerSwipeToDismiss => _miniPlayerSwipeToDismiss;

  SettingsProvider() {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_miniPlayerSwipeToDismissKey);
    if (saved != null && saved != _miniPlayerSwipeToDismiss) {
      _miniPlayerSwipeToDismiss = saved;
      notifyListeners();
    }
  }

  Future<void> setMiniPlayerSwipeToDismiss(bool value) async {
    if (value == _miniPlayerSwipeToDismiss) return;
    _miniPlayerSwipeToDismiss = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_miniPlayerSwipeToDismissKey, value);
  }
}
