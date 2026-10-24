import 'package:flutter_test/flutter_test.dart';
import 'package:tonaros/models/history_entry.dart';

HistoryEntry run(DateTime at,
        {bool completed = true, String sessionId = 's'}) =>
    HistoryEntry(
      id: '$sessionId${at.millisecondsSinceEpoch}',
      sessionId: sessionId,
      sessionName: 'S',
      endedAt: at,
      completed: completed,
      reps: 1,
      holds: 1,
      activeTime: const Duration(seconds: 30),
    );

void main() {
  final today = DateTime(2026, 3, 10, 18);

  test('round-trips through JSON', () {
    final entry = run(DateTime(2026, 3, 10, 9, 41), completed: false);
    final copy = HistoryEntry.fromJson(entry.toJson());
    expect(copy.endedAt, entry.endedAt);
    expect(copy.completed, isFalse);
    expect(copy.activeTime, const Duration(seconds: 30));
    expect(copy.sessionName, 'S');
  });

  test('no runs, no streak', () {
    final s = Streaks.of(const [], today);
    expect((s.current, s.best), (0, 0));
  });

  test('several runs on one day count once', () {
    final s = Streaks.of(
        [run(DateTime(2026, 3, 10, 8)), run(DateTime(2026, 3, 10, 19))], today);
    expect((s.current, s.best), (1, 1));
  });

  test('the current streak survives until a whole day is missed', () {
    final runs = [
      run(DateTime(2026, 3, 7, 9)),
      run(DateTime(2026, 3, 8, 9)),
      run(DateTime(2026, 3, 9, 9)),
    ];
    expect(Streaks.of(runs, today).current, 3); // nothing yet today
    expect(Streaks.of(runs, DateTime(2026, 3, 11)).current, 0);
  });

  test('best streak is the longest run of days', () {
    final s = Streaks.of([
      run(DateTime(2026, 2, 27)),
      run(DateTime(2026, 2, 28)),
      run(DateTime(2026, 3, 1)), // across a month end
      run(DateTime(2026, 3, 2)),
      run(DateTime(2026, 3, 9)),
      run(DateTime(2026, 3, 10)),
    ], today);
    expect((s.current, s.best), (2, 4));
  });

  test('stopped runs count towards a streak', () {
    final s = Streaks.of([
      run(DateTime(2026, 3, 9), completed: false),
      run(DateTime(2026, 3, 10)),
    ], today);
    expect(s.current, 2);
  });
}
