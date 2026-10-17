import 'package:flutter_test/flutter_test.dart';
import 'package:tonaros/engine/session_plan.dart';
import 'package:tonaros/engine/session_runner.dart';
import 'package:tonaros/models/session.dart';

/// A controllable [MonotonicClock]: [now] is the elapsed time.
class FakeClock {
  Duration now = const Duration(hours: 1);
  void advance(num seconds) =>
      now += Duration(milliseconds: (seconds * 1000).round());
}

/// Hold: 2 reps × 5 s, 3 s rest → transition → Tempo: 1 rep 2-1-2.
Session sampleSession({Transition transition = const Transition.countdown(10)}) =>
    Session(id: 's', name: 'S', exercises: [
      HoldExercise(
        id: 'a',
        name: 'A',
        sets: 1,
        restBetweenSets: 0,
        transition: transition,
        reps: 2,
        holdSeconds: 5,
        restBetweenReps: 3,
      ),
      const TempoExercise(
        id: 'b',
        name: 'B',
        sets: 1,
        restBetweenSets: 0,
        reps: 1,
        moveSeconds: 2,
        holdSeconds: 1,
        returnSeconds: 2,
      ),
    ]);

void main() {
  late FakeClock clock;
  late SessionRunner runner;
  late List<RunnerEvent> events;

  void setUpRunner(Session session) {
    clock = FakeClock();
    runner = SessionRunner(session, clock: () => clock.now);
    events = [];
    runner.events.listen(events.add);
  }

  /// Advances the clock and ticks, like the periodic timer would.
  void elapse(num seconds) {
    clock.advance(seconds);
    runner.tick();
  }

  tearDown(() => runner.dispose());

  test('starts with get ready, then runs phases on the wall clock', () {
    setUpRunner(sampleSession());
    runner.start();
    expect(runner.phase.kind, PhaseKind.getReady);
    expect(runner.secondsLeft, 3);

    elapse(2.95);
    expect(runner.phase.kind, PhaseKind.getReady);
    expect(runner.secondsLeft, 1);

    elapse(0.05);
    expect(runner.phase.kind, PhaseKind.hold1);
    expect(runner.secondsLeft, 5);
    expect(events.whereType<PhaseStarted>().map((e) => e.phase.kind),
        [PhaseKind.getReady, PhaseKind.hold1]);
  });

  test('timer granularity does not drift phase boundaries', () {
    setUpRunner(sampleSession());
    runner.start();
    // A late tick 0.25 s after get ready ended: hold has 4.75 s left, not 5.
    elapse(3.25);
    expect(runner.phase.kind, PhaseKind.hold1);
    expect(runner.remaining, const Duration(milliseconds: 4750));
  });

  test('catches up after time in the background, announcing once', () {
    setUpRunner(sampleSession());
    runner.start();
    events.clear();
    // 3 get ready + 5 hold + 3 rest + 5 hold = 16 s, then 4 s into the
    // 10 s transition.
    elapse(20);
    expect(runner.phase.kind, PhaseKind.transition);
    expect(runner.secondsLeft, 6);
    final started = events.whereType<PhaseStarted>().single;
    expect(started.caughtUp, isTrue);
    expect(runner.holdsDone, 2);
    expect(runner.repsDone, 2);
  });

  test('pause keeps the time left; resume continues from it', () {
    setUpRunner(sampleSession());
    runner.start();
    elapse(4); // 1 s into hold
    runner.pause();
    expect(runner.status, RunnerStatus.paused);
    elapse(60);
    expect(runner.phase.kind, PhaseKind.hold1);
    expect(runner.secondsLeft, 4);

    runner.resume();
    elapse(4);
    expect(runner.phase.kind, PhaseKind.rest);
    // Paused time doesn't count.
    expect(runner.activeTime, const Duration(seconds: 8));
  });

  test('"wait until tap" stops the clock until skipped', () {
    setUpRunner(sampleSession(transition: const Transition.tap()));
    runner.start();
    elapse(100);
    expect(runner.phase.kind, PhaseKind.waitForTap);
    expect(runner.status, RunnerStatus.waitingForTap);
    // Active time stops at the end of the exercise, not at "now".
    expect(runner.activeTime, const Duration(seconds: 16));

    runner.skipPhase();
    expect(runner.phase.kind, PhaseKind.move);
    expect(runner.status, RunnerStatus.running);
    expect(runner.secondsLeft, 2);
  });

  test('skip phase does not count the skipped hold', () {
    setUpRunner(sampleSession());
    runner.start();
    elapse(3);
    runner.skipPhase();
    expect(runner.phase.kind, PhaseKind.rest);
    expect(events.last, isA<PhaseStarted>().having((e) => e.skipped, 'skipped', true));
    expect(runner.holdsDone, 0);
  });

  test('skip exercise jumps past the transition to the next exercise', () {
    setUpRunner(sampleSession());
    runner.start();
    elapse(4);
    runner.skipExercise();
    expect(runner.phase.kind, PhaseKind.move);
    expect(runner.exercise.name, 'B');

    runner.skipExercise();
    expect(runner.status, RunnerStatus.finished);
    // Skipped past the end: stopped early, no "finished" fanfare.
    expect(runner.completed, isFalse);
    expect(events.whereType<SessionFinished>(), isEmpty);
  });

  test('skipping while paused stays paused at the new phase', () {
    setUpRunner(sampleSession());
    runner.start();
    elapse(4);
    runner.pause();
    runner.skipPhase();
    expect(runner.status, RunnerStatus.paused);
    expect(runner.phase.kind, PhaseKind.rest);
    expect(runner.secondsLeft, 3);
  });

  test('runs to the end and reports totals', () {
    setUpRunner(sampleSession());
    runner.start();
    elapse(3 + 13 + 10 + 5);
    expect(runner.status, RunnerStatus.finished);
    expect(events.last, isA<SessionFinished>());
    expect(runner.completed, isTrue);
    expect(runner.holdsDone, 3); // 2 holds + 1 tempo hold
    expect(runner.repsDone, 3);
    expect(runner.activeTime, const Duration(seconds: 31));
  });

  test('stop ends without a finished cue', () {
    setUpRunner(sampleSession());
    runner.start();
    runner.stop();
    expect(runner.status, RunnerStatus.finished);
    expect(events.whereType<SessionFinished>(), isEmpty);
  });

  test('a tap rest between sets waits, then starts the next set', () {
    setUpRunner(Session(id: 's', name: 'S', exercises: [
      const HoldExercise(
        id: 'a',
        name: 'A',
        sets: 2,
        restBetweenSets: 30,
        tapBetweenSets: true,
        reps: 1,
        holdSeconds: 5,
        restBetweenReps: 0,
      ),
    ]));
    runner.start();
    elapse(3 + 5 + 100);
    expect(runner.phase.kind, PhaseKind.setRest);
    expect(runner.status, RunnerStatus.waitingForTap);
    expect(runner.activeTime, const Duration(seconds: 8));

    runner.skipPhase();
    expect(runner.phase.kind, PhaseKind.hold1);
    expect(runner.phase.set, 2);
    expect(runner.status, RunnerStatus.running);
    elapse(5);
    expect(runner.status, RunnerStatus.finished);
    expect(runner.holdsDone, 2);
  });

  test('a skip while paused is announced on resume, not while paused', () {
    setUpRunner(sampleSession());
    runner.start();
    elapse(4);
    runner.pause();
    events.clear();
    runner.skipPhase();
    expect(runner.phase.kind, PhaseKind.rest);
    expect(events.whereType<PhaseStarted>(), isEmpty);

    runner.resume();
    expect(
      events.whereType<PhaseStarted>().single,
      isA<PhaseStarted>()
          .having((e) => e.phase.kind, 'kind', PhaseKind.rest)
          .having((e) => e.skipped, 'skipped', true),
    );
  });

  test('reps still count when the rep-ending phase has 0 s', () {
    // Two holds, but hold 2 is 0 s (e.g. older saved data): the rest after
    // hold 1 is the rep's last phase.
    setUpRunner(Session(id: 's', name: 'S', exercises: [
      const HoldExercise(
        id: 'a',
        name: 'A',
        sets: 1,
        restBetweenSets: 0,
        reps: 2,
        holdSeconds: 2,
        restBetweenReps: 1,
        twoHolds: true,
        secondHoldSeconds: 0,
      ),
    ]));
    runner.start();
    elapse(3 + 2 + 1 + 1 + 2 + 1);
    expect(runner.status, RunnerStatus.finished);
    expect(runner.repsDone, 2);
  });

  test('pause first catches up a phase whose end has passed', () {
    setUpRunner(sampleSession());
    runner.start();
    // 1 s past the end of get ready, with no tick in between.
    clock.advance(4);
    runner.pause();
    expect(runner.phase.kind, PhaseKind.hold1);
    expect(runner.remaining, const Duration(seconds: 4));
  });

  test('the timer only runs while the clock does', () {
    setUpRunner(sampleSession(transition: const Transition.tap()));
    runner.start();
    expect(runner.isTimerRunning, isTrue);
    runner.pause();
    expect(runner.isTimerRunning, isFalse);
    runner.resume();
    expect(runner.isTimerRunning, isTrue);
    elapse(100); // into the wait-for-tap transition
    expect(runner.status, RunnerStatus.waitingForTap);
    expect(runner.isTimerRunning, isFalse);
    runner.skipPhase();
    expect(runner.isTimerRunning, isTrue);
    runner.stop();
    expect(runner.isTimerRunning, isFalse);
  });

  test('during a transition, the upcoming exercise is shown', () {
    setUpRunner(sampleSession());
    runner.start();
    expect(runner.displayExerciseIndex, 0); // get ready: the first
    elapse(3 + 13 + 1);
    expect(runner.phase.kind, PhaseKind.transition);
    expect(runner.phase.exerciseIndex, 0);
    expect(runner.displayExerciseIndex, 1);
  });
}
