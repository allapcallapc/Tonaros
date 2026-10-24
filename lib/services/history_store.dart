import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_entry.dart';

/// Every recorded run, newest first, persisted as JSON in shared
/// preferences (local storage on web). Every change is saved immediately.
class HistoryStore extends ChangeNotifier {
  HistoryStore(this._prefs) {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    // Same recovery as SessionStore: never crash on launch, keep what can
    // be read, back up the rest under a timestamped key.
    List<Object?> list;
    try {
      list = jsonDecode(raw) as List;
    } on Object catch (e) {
      debugPrint('HistoryStore: could not read saved history: $e');
      _quarantine(raw);
      return;
    }
    final unreadable = <Object?>[];
    for (final entry in list) {
      try {
        _entries.add(HistoryEntry.fromJson(entry as Map<String, dynamic>));
      } on Object catch (e) {
        debugPrint('HistoryStore: skipping an unreadable entry: $e');
        unreadable.add(entry);
      }
    }
    _entries.sort((a, b) => b.endedAt.compareTo(a.endedAt));
    if (unreadable.isNotEmpty) _quarantine(jsonEncode(unreadable));
  }

  void _quarantine(String unreadable) {
    _prefs.setString(
      '$_key.corrupt.${DateTime.now().millisecondsSinceEpoch}',
      unreadable,
    );
    _prefs.setString(_key, _encode());
  }

  String _encode() => jsonEncode([for (final e in _entries) e.toJson()]);

  static const _key = 'history';

  final SharedPreferences _prefs;
  List<HistoryEntry> _entries = [];

  /// Newest first.
  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  /// Newest first; every run when [sessionId] is null.
  List<HistoryEntry> entriesFor(String? sessionId) => sessionId == null
      ? entries
      : List.unmodifiable(_entries.where((e) => e.sessionId == sessionId));

  /// Also puts a deleted entry back (undo), in its place by date.
  Future<void> add(HistoryEntry entry) async {
    _entries = [..._entries, entry]
      ..sort((a, b) => b.endedAt.compareTo(a.endedAt));
    await _save();
  }

  Future<void> delete(String id) async {
    _entries = _entries.where((e) => e.id != id).toList();
    await _save();
  }

  /// Clears one session's runs, or every run when [sessionId] is null.
  Future<void> clear({String? sessionId}) async {
    _entries = sessionId == null
        ? []
        : _entries.where((e) => e.sessionId != sessionId).toList();
    await _save();
  }

  Future<void> _save() async {
    notifyListeners();
    await _prefs.setString(_key, _encode());
  }
}
