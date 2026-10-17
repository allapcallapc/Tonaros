import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/session.dart';

/// All saved sessions, persisted as JSON in shared preferences (local
/// storage on web). Every change is saved immediately.
class SessionStore extends ChangeNotifier {
  SessionStore(this._prefs) {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    // Never crash on launch over unreadable data. Each session is read on
    // its own so one bad record doesn't lose the rest; whatever couldn't be
    // read is moved to a backup key.
    List<Object?> entries;
    try {
      entries = jsonDecode(raw) as List;
    } on Object catch (e) {
      debugPrint('SessionStore: could not read saved sessions: $e');
      _quarantine(raw);
      return;
    }
    final unreadable = <Object?>[];
    for (final entry in entries) {
      try {
        _sessions.add(Session.fromJson(entry as Map<String, dynamic>));
      } on Object catch (e) {
        debugPrint('SessionStore: skipping an unreadable session: $e');
        unreadable.add(entry);
      }
    }
    if (unreadable.isNotEmpty) _quarantine(jsonEncode(unreadable));
  }

  /// Keeps [unreadable] under its own timestamped key (so a later problem
  /// never replaces an earlier backup), then saves only the readable
  /// sessions so the same data isn't backed up again on every launch.
  void _quarantine(String unreadable) {
    _prefs.setString(
        '$_key.corrupt.${DateTime.now().millisecondsSinceEpoch}', unreadable);
    _prefs.setString(_key, _encode());
  }

  String _encode() => jsonEncode([for (final s in _sessions) s.toJson()]);

  static const _key = 'sessions';

  final SharedPreferences _prefs;
  List<Session> _sessions = [];

  List<Session> get sessions => List.unmodifiable(_sessions);

  Session? byId(String id) {
    for (final s in _sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<Session> create(String name) async {
    final session = Session(id: newId(), name: name, exercises: const []);
    _sessions = [..._sessions, session];
    await _save();
    return session;
  }

  /// Inserts the copy right after the original.
  Future<Session> duplicate(Session session) async {
    final copy = session.duplicate('${session.name} (copy)');
    final index = _sessions.indexWhere((s) => s.id == session.id);
    _sessions = [..._sessions]..insert(index + 1, copy);
    await _save();
    return copy;
  }

  Future<void> update(Session session) async {
    _sessions = [
      for (final s in _sessions) s.id == session.id ? session : s,
    ];
    await _save();
  }

  Future<void> delete(String id) async {
    _sessions = _sessions.where((s) => s.id != id).toList();
    await _save();
  }

  Future<void> _save() async {
    notifyListeners();
    await _prefs.setString(_key, _encode());
  }
}
