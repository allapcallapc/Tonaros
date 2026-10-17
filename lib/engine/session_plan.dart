import '../models/session.dart';

enum PhaseKind {
  getReady,

  /// A Hold exercise's (first) hold.
  hold1,

  /// The second hold of a two-hold rep.
  hold2,

  /// Rest between reps, or between the two holds of a rep.
  rest,

  /// Rest between sets.
  setRest,
  move,
  tempoHold,
  back,
  transition,

  /// A "wait until tap" transition between exercises.
  waitForTap,
}

/// One step of a running session.
class Phase {
  const Phase({
    required this.kind,
    required this.label,
    required this.seconds,
    this.exerciseIndex = 0,
    this.set = 0,
    this.rep = 0,
    this.repsDone = 0,
    this.waitsForTap = false,
    this.endsRep = false,
  });

  final PhaseKind kind;
  final String label;

  /// Duration; 0 when it [waitsForTap].
  final int seconds;

  /// Index of the exercise this phase belongs to (for transitions, the one
  /// just finished; for get-ready, the first).
  final int exerciseIndex;

  /// 1-based set/rep, or 0 when not inside a set/rep.
  final int set;
  final int rep;

  /// Reps completed in the current set while this phase runs. Halves mark a
  /// two-hold rep whose first hold is done.
  final double repsDone;

  /// No countdown: runs until the user taps to continue (a "wait until
  /// tap" transition, or a tap rest between sets).
  final bool waitsForTap;

  /// Completing this phase completes a rep (its last hold or return).
  final bool endsRep;

  bool get isHold =>
      kind == PhaseKind.hold1 ||
      kind == PhaseKind.hold2 ||
      kind == PhaseKind.tempoHold;
}

const getReadySeconds = 3;

/// Every phase of [session], in order, starting with the get-ready
/// countdown. Zero-length phases are left out.
List<Phase> buildPlan(Session session) {
  final phases = <Phase>[];
  final exercises = session.exercises;
  if (exercises.isEmpty) return phases;
  phases.add(const Phase(
    kind: PhaseKind.getReady,
    label: 'Get ready',
    seconds: getReadySeconds,
  ));
  for (var i = 0; i < exercises.length; i++) {
    phases.addAll(exercisePhases(exercises[i], i));
    if (i < exercises.length - 1) {
      final t = exercises[i].transition;
      if (t.kind == TransitionKind.tap) {
        phases.add(Phase(
          kind: PhaseKind.waitForTap,
          label: 'Tap when ready',
          seconds: 0,
          exerciseIndex: i,
          waitsForTap: true,
        ));
      } else if (t.seconds > 0) {
        phases.add(Phase(
          kind: PhaseKind.transition,
          label: 'Next exercise',
          seconds: t.seconds,
          exerciseIndex: i,
        ));
      }
    }
  }
  return phases;
}

/// The phases of a single exercise (no get-ready, no transition).
List<Phase> exercisePhases(Exercise exercise, [int exerciseIndex = 0]) {
  final phases = <Phase>[];
  void add(PhaseKind kind, String label, int seconds, int set, int rep,
      double repsDone) {
    if (seconds <= 0) return;
    phases.add(Phase(
      kind: kind,
      label: label,
      seconds: seconds,
      exerciseIndex: exerciseIndex,
      set: set,
      rep: rep,
      repsDone: repsDone,
    ));
  }

  // Completing the last phase actually added for a rep completes the rep
  // - whichever it is, since zero-length phases are left out.
  void endRep(int repStart) {
    if (phases.length == repStart) return;
    final p = phases.removeLast();
    phases.add(Phase(
      kind: p.kind,
      label: p.label,
      seconds: p.seconds,
      exerciseIndex: p.exerciseIndex,
      set: p.set,
      rep: p.rep,
      repsDone: p.repsDone,
      endsRep: true,
    ));
  }

  for (var set = 1; set <= exercise.sets; set++) {
    for (var rep = 1; rep <= exercise.reps; rep++) {
      final before = (rep - 1).toDouble();
      final lastRep = rep == exercise.reps;
      final repStart = phases.length;
      switch (exercise) {
        case HoldExercise e:
          if (e.twoHolds) {
            add(PhaseKind.hold1, e.firstHoldName, e.holdSeconds, set, rep,
                before);
            add(PhaseKind.rest, 'Rest', e.restBetweenReps, set, rep,
                before + 0.5);
            add(PhaseKind.hold2, e.secondHoldName, e.secondHoldSeconds, set,
                rep, before + 0.5);
          } else {
            add(PhaseKind.hold1, 'Hold', e.holdSeconds, set, rep, before);
          }
          endRep(repStart);
          // The last rep's rest is replaced by the rest between sets.
          if (!lastRep) {
            add(PhaseKind.rest, 'Rest', e.restBetweenReps, set, rep,
                rep.toDouble());
          }
        case TempoExercise e:
          add(PhaseKind.move, 'Move', e.moveSeconds, set, rep, before);
          add(PhaseKind.tempoHold, 'Hold', e.holdSeconds, set, rep, before);
          add(PhaseKind.back, 'Back', e.returnSeconds, set, rep, before);
          endRep(repStart);
      }
    }
    if (set < exercise.sets) {
      if (exercise.tapBetweenSets) {
        phases.add(Phase(
          kind: PhaseKind.setRest,
          label: 'Set rest',
          seconds: 0,
          exerciseIndex: exerciseIndex,
          set: set,
          rep: exercise.reps,
          repsDone: exercise.reps.toDouble(),
          waitsForTap: true,
        ));
      } else {
        add(PhaseKind.setRest, 'Set rest', exercise.restBetweenSets, set,
            exercise.reps, exercise.reps.toDouble());
      }
    }
  }
  return phases;
}

/// Estimated running time of [session]: every timed phase, including the
/// get-ready countdown, plus how many "wait until tap" transitions add an
/// unknown amount on top.
({Duration duration, int taps}) estimateSession(Session session) {
  final plan = buildPlan(session);
  return (
    duration: Duration(
        seconds: plan.fold(0, (total, phase) => total + phase.seconds)),
    taps: plan.where((p) => p.waitsForTap).length,
  );
}

Duration estimateExercise(Exercise exercise) => Duration(
    seconds: exercisePhases(exercise)
        .fold(0, (total, phase) => total + phase.seconds));

/// "45 s", "3 min", "12 min 30 s", "1 h 5 min".
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return m > 0 ? '$h h $m min' : '$h h';
  if (m > 0) return s > 0 ? '$m min $s s' : '$m min';
  return '$s s';
}
