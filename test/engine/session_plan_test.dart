import 'package:flutter_test/flutter_test.dart';
import 'package:tonaros/engine/session_plan.dart';
import 'package:tonaros/models/session.dart';

HoldExercise hold({
  int sets = 1,
  int reps = 2,
  int hold = 5,
  int rest = 3,
  int setRest = 30,
  bool twoHolds = false,
  int hold2 = 4,
  Transition transition = const Transition.countdown(10),
}) =>
    HoldExercise(
      id: 'h',
      name: 'Hold ex',
      sets: sets,
      restBetweenSets: setRest,
      transition: transition,
      reps: reps,
      holdSeconds: hold,
      restBetweenReps: rest,
      twoHolds: twoHolds,
      secondHoldSeconds: hold2,
    );

TempoExercise tempo({int sets = 1, int reps = 2, int holdS = 1}) =>
    TempoExercise(
      id: 't',
      name: 'Tempo ex',
      sets: sets,
      restBetweenSets: 20,
      reps: reps,
      moveSeconds: 3,
      holdSeconds: holdS,
      returnSeconds: 2,
    );

String describe(List<Phase> phases) => phases
    .map((p) => '${p.kind.name}:${p.seconds}@${p.set}.${p.rep}')
    .join(' ');

void main() {
  test('single hold: last rep rest replaced by set rest', () {
    expect(
      describe(exercisePhases(hold(sets: 2))),
      'hold1:5@1.1 rest:3@1.1 hold1:5@1.2 setRest:30@1.2 '
      'hold1:5@2.1 rest:3@2.1 hold1:5@2.2',
    );
  });

  test('two holds: hold 1 → rest → hold 2 → rest → next rep', () {
    final phases = exercisePhases(hold(twoHolds: true));
    expect(
      describe(phases),
      'hold1:5@1.1 rest:3@1.1 hold2:4@1.1 rest:3@1.1 '
      'hold1:5@1.2 rest:3@1.2 hold2:4@1.2',
    );
    expect(phases.map((p) => p.label).take(3), ['Left', 'Rest', 'Right']);
    // The dot fills halfway after hold 1, fully after hold 2.
    expect(phases.map((p) => p.repsDone), [0, 0.5, 0.5, 1, 1, 1.5, 1.5]);
  });

  test('zero-length rests are skipped', () {
    expect(describe(exercisePhases(hold(rest: 0, sets: 2, setRest: 0))),
        'hold1:5@1.1 hold1:5@1.2 hold1:5@2.1 hold1:5@2.2');
  });

  test('tempo: move → hold → back, no rest between reps; 0 s hold skipped',
      () {
    expect(describe(exercisePhases(tempo())),
        'move:3@1.1 tempoHold:1@1.1 back:2@1.1 move:3@1.2 tempoHold:1@1.2 back:2@1.2');
    expect(describe(exercisePhases(tempo(holdS: 0, reps: 1, sets: 2))),
        'move:3@1.1 back:2@1.1 setRest:20@1.1 move:3@2.1 back:2@2.1');
  });

  test('session: get ready, transitions between exercises only', () {
    final session = Session(id: 's', name: 'S', exercises: [
      hold(reps: 1),
      hold(reps: 1, transition: const Transition.tap()),
      tempo(reps: 1),
    ]);
    expect(
      describe(buildPlan(session)),
      'getReady:3@0.0 hold1:5@1.1 transition:10@0.0 '
      'hold1:5@1.1 waitForTap:0@0.0 '
      'move:3@1.1 tempoHold:1@1.1 back:2@1.1',
    );
    final estimate = estimateSession(session);
    expect(estimate.duration, const Duration(seconds: 3 + 5 + 10 + 5 + 6));
    expect(estimate.taps, 1);
  });

  test('empty session has no phases', () {
    expect(buildPlan(const Session(id: 's', name: 'S', exercises: [])),
        isEmpty);
  });

  test('formatDuration', () {
    expect(formatDuration(const Duration(seconds: 45)), '45 s');
    expect(formatDuration(const Duration(minutes: 3)), '3 min');
    expect(formatDuration(const Duration(seconds: 750)), '12 min 30 s');
    expect(formatDuration(const Duration(minutes: 65)), '1 h 5 min');
  });

  test('tap rest between sets waits instead of counting down', () {
    final phases =
        exercisePhases(hold(sets: 2, reps: 1).copyWith(tapBetweenSets: true));
    expect(describe(phases), 'hold1:5@1.1 setRest:0@1.1 hold1:5@2.1');
    expect(phases.map((p) => p.waitsForTap), [false, true, false]);

    final estimate = estimateSession(Session(id: 's', name: 'S', exercises: [
      hold(sets: 3, reps: 1).copyWith(tapBetweenSets: true),
    ]));
    expect(estimate.duration, const Duration(seconds: 3 + 3 * 5));
    expect(estimate.taps, 2);
  });
}
