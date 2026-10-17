import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/session.dart';

/// All saved sessions, persisted as JSON in shared preferences (local
/// storage on web). Every change is saved immediately.
class SessionStore extends ChangeNotifier {
  SessionStore(this._prefs) {
    final raw = _prefs.getString(_key);
    if (raw != null) {
      try {
        _sessions = [
          for (final s in jsonDecode(raw) as List)
            Session.fromJson(s as Map<String, dynamic>),
        ];
      } on Object catch (e) {
        // Never crash on launch over unreadable data; start empty but keep
        // the raw value around so it isn't silently overwritten.
        debugPrint('SessionStore: could not read saved sessions: $e');
        _prefs.setString('$_key.corrupt', raw);
      }
    }
  }

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
    await _prefs.setString(
      _key,
      jsonEncode([for (final s in _sessions) s.toJson()]),
    );
  }
}
