import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences, persisted in shared preferences.
class SettingsStore extends ChangeNotifier {
  SettingsStore(this._prefs);

  final SharedPreferences _prefs;

  ThemeMode get themeMode => ThemeMode.values.firstWhere(
        (m) => m.name == _prefs.getString('themeMode'),
        orElse: () => ThemeMode.system,
      );

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString('themeMode', mode.name);
    notifyListeners();
  }
}
