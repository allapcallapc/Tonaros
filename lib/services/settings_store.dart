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

  /// Cue sounds while a session runs.
  bool get soundOn => _prefs.getBool('soundOn') ?? true;

  Future<void> setSoundOn(bool value) async {
    await _prefs.setBool('soundOn', value);
    notifyListeners();
  }

  /// Cue vibrations while a session runs.
  bool get vibrationOn => _prefs.getBool('vibrationOn') ?? true;

  Future<void> setVibrationOn(bool value) async {
    await _prefs.setBool('vibrationOn', value);
    notifyListeners();
  }
}
