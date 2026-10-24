import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_entry.dart';
import 'stored_list.dart';

/// Every recorded run, newest first, persisted as JSON in shared
/// preferences (local storage on web). Every change is saved immediately.
class HistoryStore extends ChangeNotifier {
  HistoryStore(this._prefs)
      : _entries = readStoredList(_prefs, _key,
            fromJson: HistoryEntry.fromJson, toJson: (e) => e.toJson())
          ..sort((a, b) => b.endedAt.compareTo(a.endedAt));

  String _encode() => jsonEncode([for (final e in _entries) e.toJson()]);

  static const _key = 'history';

  final SharedPreferences _prefs;
  List<HistoryEntry> _entries;

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
