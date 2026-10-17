import '../engine/session_plan.dart';
import '../models/session.dart';

/// One-line description, e.g. "3 sets × 10 reps · hold 5 s · rest 5 s".
String exerciseSummary(Exercise exercise) {
  final sets = exercise.sets == 1 ? '1 set' : '${exercise.sets} sets';
  final reps = exercise.reps == 1 ? '1 rep' : '${exercise.reps} reps';
  final parts = ['$sets × $reps'];
  switch (exercise) {
    case HoldExercise e:
      parts.add(e.twoHolds
          ? '${e.firstHoldName} ${e.holdSeconds} s / '
              '${e.secondHoldName} ${e.secondHoldSeconds} s'
          : 'hold ${e.holdSeconds} s');
      if (e.restBetweenReps > 0) parts.add('rest ${e.restBetweenReps} s');
    case TempoExercise e:
      parts.add('${e.moveSeconds}-${e.holdSeconds}-${e.returnSeconds} s');
  }
  if (exercise.sets > 1 && exercise.tapBetweenSets) {
    parts.add('tap between sets');
  }
  return parts.join(' · ');
}

String transitionLabel(Transition t) => t.kind == TransitionKind.tap
    ? 'Wait for tap'
    : t.seconds == 0
        ? 'No pause'
        : '${formatDuration(Duration(seconds: t.seconds))} countdown';

/// "≈ 12 min 30 s", plus "+ 2 taps" for "wait until tap" transitions.
String sessionDurationLabel(Session session) {
  final estimate = estimateSession(session);
  final taps = switch (estimate.taps) {
    0 => '',
    1 => ' + 1 tap',
    final n => ' + $n taps',
  };
  return '≈ ${formatDuration(estimate.duration)}$taps';
}
