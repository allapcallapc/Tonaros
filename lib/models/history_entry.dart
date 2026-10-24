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

  /// Local wall-clock time the run ended; its day is the one it counts
  /// towards. Stored without a time zone, so a run keeps its day (and
  /// time) if the device's time zone changes later.
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
        endedAt: DateTime.parse(json['endedAt'] as String),
        completed: json['completed'] as bool,
        reps: json['reps'] as int,
        holds: json['holds'] as int,
        activeTime: Duration(milliseconds: json['activeMs'] as int),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'sessionName': sessionName,
        // No offset in a local DateTime's ISO string: parsed back as the
        // same wall-clock time in whatever zone the device is in then.
        'endedAt': endedAt.toLocal().toIso8601String(),
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
    final today = dayOf(now);
    // A run dated after today (the clock was wrong, or moved back since)
    // would otherwise end every streak in the future and zero the current.
    final days = {
      for (final e in entries)
        if (!dayOf(e.endedAt).isAfter(today)) dayOf(e.endedAt),
    }.toList()
      ..sort();
    var best = 0;
    var run = 0;
    DateTime? previous;
    for (final day in days) {
      run = previous != null && _daysBetween(previous, day) == 1 ? run + 1 : 1;
      if (run > best) best = run;
      previous = day;
    }
    final alive = previous != null &&
        (previous == today || _daysBetween(previous, today) == 1);
    return Streaks(current: alive ? run : 0, best: best);
  }
}

/// Whole calendar days from [a] to [b], both at local midnight. Rounded, so
/// a daylight saving change (a 23 or 25 hour day) still counts as one.
int _daysBetween(DateTime a, DateTime b) =>
    (b.difference(a).inMinutes / Duration.minutesPerDay).round();
