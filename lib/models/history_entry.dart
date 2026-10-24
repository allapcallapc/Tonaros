import 'session.dart';

/// One run of a session, recorded when it ends (completed or stopped).
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.sessionId,
    required this.sessionName,
    required this.endedAt,
    required this.completed,
    required this.reps,
    required this.holds,
    required this.activeTime,
  });

  final String id;

  /// May no longer exist: history outlives a deleted session.
  final String sessionId;

  /// The session's name at the time, kept even if it's renamed later.
  final String sessionName;

  /// Local time the run ended; its day is the one it counts towards.
  final DateTime endedAt;

  /// False when stopped early.
  final bool completed;
  final int reps;
  final int holds;
  final Duration activeTime;

  factory HistoryEntry.record({
    required Session session,
    required DateTime endedAt,
    required bool completed,
    required int reps,
    required int holds,
    required Duration activeTime,
  }) =>
      HistoryEntry(
        id: newId(),
        sessionId: session.id,
        sessionName: session.name,
        endedAt: endedAt,
        completed: completed,
        reps: reps,
        holds: holds,
        activeTime: activeTime,
      );

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String,
        sessionName: json['sessionName'] as String,
        endedAt: DateTime.fromMillisecondsSinceEpoch(json['endedAt'] as int),
        completed: json['completed'] as bool,
        reps: json['reps'] as int,
        holds: json['holds'] as int,
        activeTime: Duration(milliseconds: json['activeMs'] as int),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'sessionName': sessionName,
        'endedAt': endedAt.millisecondsSinceEpoch,
        'completed': completed,
        'reps': reps,
        'holds': holds,
        'activeMs': activeTime.inMilliseconds,
      };
}

/// Midnight (local) of [t]'s day.
DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// Consecutive days with at least one run.
class Streaks {
  const Streaks({required this.current, required this.best});

  /// Runs up to today, or up to yesterday if nothing's been done yet today
  /// (the streak isn't broken until a whole day is missed).
  final int current;
  final int best;

  factory Streaks.of(Iterable<HistoryEntry> entries, DateTime now) {
    final days = {for (final e in entries) dayOf(e.endedAt)}.toList()..sort();
    var best = 0;
    var run = 0;
    DateTime? previous;
    for (final day in days) {
      run = previous != null && _daysBetween(previous, day) == 1 ? run + 1 : 1;
      if (run > best) best = run;
      previous = day;
    }
    final today = dayOf(now);
    final alive = previous != null &&
        (previous == today || _daysBetween(previous, today) == 1);
    return Streaks(current: alive ? run : 0, best: best);
  }
}

/// Whole calendar days from [a] to [b], both at local midnight. Rounded, so
/// a daylight saving change (a 23 or 25 hour day) still counts as one.
int _daysBetween(DateTime a, DateTime b) =>
    (b.difference(a).inMinutes / Duration.minutesPerDay).round();
