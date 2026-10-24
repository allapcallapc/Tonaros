import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads the JSON list saved under [key] in shared preferences.
///
/// Never crashes on launch over unreadable data. Each item is read on its
/// own so one bad record doesn't lose the rest; whatever couldn't be read
/// is kept under its own timestamped backup key (so a later problem never
/// replaces an earlier backup), then only the readable items are saved
/// back, so the same data isn't backed up again on every launch.
List<T> readStoredList<T>(
  SharedPreferences prefs,
  String key, {
  required T Function(Map<String, dynamic> json) fromJson,
  required Map<String, dynamic> Function(T item) toJson,
}) {
  final raw = prefs.getString(key);
  if (raw == null) return [];
  final items = <T>[];
  String? unreadable;
  try {
    final bad = <Object?>[];
    for (final entry in jsonDecode(raw) as List) {
      try {
        items.add(fromJson(entry as Map<String, dynamic>));
      } on Object catch (e) {
        debugPrint('"$key": skipping an unreadable item: $e');
        bad.add(entry);
      }
    }
    if (bad.isNotEmpty) unreadable = jsonEncode(bad);
  } on Object catch (e) {
    debugPrint('"$key": could not read saved data: $e');
    unreadable = raw;
  }
  if (unreadable != null) {
    prefs.setString(
        '$key.corrupt.${DateTime.now().millisecondsSinceEpoch}', unreadable);
    prefs.setString(key, jsonEncode([for (final i in items) toJson(i)]));
  }
  return items;
}
