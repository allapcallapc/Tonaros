import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tonaros/services/history_store.dart';

import '../test_app.dart' show run;

void main() {
  Future<HistoryStore> store([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    return HistoryStore(await SharedPreferences.getInstance());
  }

  test('newest first, and survives a reload', () async {
    final s = await store();
    await s.add(run(DateTime(2026, 3, 1)));
    await s.add(run(DateTime(2026, 3, 3)));
    await s.add(run(DateTime(2026, 3, 2)));

    final reloaded = HistoryStore(await SharedPreferences.getInstance());
    expect(reloaded.entries.map((e) => e.endedAt.day), [3, 2, 1]);
  });

  test('filters, deletes and clears by session', () async {
    final s = await store();
    final a = run(DateTime(2026, 3, 1));
    await s.add(a);
    final b = run(DateTime(2026, 3, 2));
    await s.add(b);
    final other = run(DateTime(2026, 3, 3), sessionId: 'x');
    await s.add(other);

    expect(s.entriesFor('s').length, 2);
    expect(s.entriesFor(null).length, 3);

    await s.delete(a.id);
    expect(s.entriesFor('s').single.id, b.id);

    await s.clear(sessionId: 's');
    expect(s.entries.single.sessionId, 'x');

    await s.clear();
    expect(s.entries, isEmpty);
  });

  test('unreadable entries are skipped and backed up', () async {
    final s = await store({
      'history': '[{"id": 1}, ${'{"id":"a","sessionId":"s","sessionName":"S",'
          '"endedAt":"2026-03-01T08:00:00.000","completed":true,"reps":1,"holds":0,"activeMs":1000}'}]',
    });
    expect(s.entries.single.id, 'a');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('history.corrupt.')),
        hasLength(1));
  });
}
