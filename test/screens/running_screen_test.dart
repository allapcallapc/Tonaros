import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonaros/app_scope.dart';
import 'package:tonaros/models/session.dart';
import 'package:tonaros/screens/running_screen.dart';
import 'package:tonaros/screens/summary_screen.dart';
import 'package:tonaros/widgets/phase_ring.dart';
import 'package:tonaros/services/cues.dart';
import 'package:tonaros/widgets/rep_dots.dart';
import 'package:tonaros/widgets/tempo_curve.dart';

import '../engine/session_runner_test.dart' show FakeClock, sampleSession;
import '../test_app.dart';

void main() {
  late FakeClock clock;
  late FakeCueOutput cues;
  late FakeBackgroundSession background;

  /// The wall clock follows the fake timer clock unless frozen.
  var wallClockFrozen = false;
  final wallClockStart = DateTime(2026, 3, 10, 9, 41);
  late Duration wallClockFrozenAt;

  Future<void> pumpRunning(WidgetTester tester, Session session) async {
    clock = FakeClock();
    final clockStart = clock.now;
    wallClockFrozen = false;
    cues = FakeCueOutput();
    background = FakeBackgroundSession();
    await tester.pumpWidget(await withAppScope(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  RunningScreen(
                    session: session,
                    clock: () => clock.now,
                    now: () => wallClockStart.add(
                        (wallClockFrozen ? wallClockFrozenAt : clock.now) -
                            clockStart),
                    cueOutput: cues,
                    background: background,
                  ),
            ),
          ),
          child: const Text('go'),
        ),
      ),
    )));
    await tester.tap(find.text('go'));
    // Not pumpAndSettle: the ring repaints every frame while running.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Moves the fake wall clock and lets the runner's timer fire.
  Future<void> elapse(WidgetTester tester, num seconds) async {
    clock.advance(seconds);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
  }

  testWidgets('get ready, then the first hold with rep counter and dots',
      (tester) async {
    await pumpRunning(tester, sampleSession());
    expect(find.text('GET READY'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Exercise 1/2'), findsOneWidget);
    expect(find.text('Next: A'), findsOneWidget);

    await elapse(tester, 3);
    expect(find.text('HOLD'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Rep 1/2'), findsOneWidget);
    expect(find.byType(RepDots), findsOneWidget);
    expect(find.text('Next: Rest · 3 s'), findsOneWidget);
  });

  testWidgets('pause freezes the countdown, resume continues', (tester) async {
    await pumpRunning(tester, sampleSession());
    await elapse(tester, 4); // 1 s into the hold: 4 left
    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.pump();
    await elapse(tester, 30);
    // Paused: once the button ripple settles, nothing schedules frames.
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.text('4'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Resume'));
    await elapse(tester, 1);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('wait-for-tap transition shows Continue', (tester) async {
    await pumpRunning(
        tester, sampleSession(transition: const Transition.tap()));
    await elapse(tester, 16);
    expect(find.text('TAP WHEN READY'), findsOneWidget);
    expect(find.text('Next: B'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('MOVE'), findsOneWidget);
  });

  testWidgets('finishing shows the summary', (tester) async {
    await pumpRunning(tester, sampleSession());
    await elapse(tester, 3 + 13 + 10 + 5);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SummaryScreen), findsOneWidget);
    expect(find.text('Session complete'), findsOneWidget);
    expect(find.text('31 s'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('stop asks first, then shows what was done', (tester) async {
    await pumpRunning(tester, sampleSession());
    await elapse(tester, 9); // first hold done
    await tester.tap(find.byTooltip('Stop'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Stop').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Session stopped'), findsOneWidget);
    expect(
      find.descendant(
          of: find.byType(SummaryScreen), matching: find.text('1')),
      findsNWidgets(2), // 1 rep, 1 hold
    );
  });

  testWidgets('tempo reps show the tempo curve instead of the ring',
      (tester) async {
    await pumpRunning(tester, sampleSession());
    await elapse(tester, 3);
    expect(find.byType(PhaseRing), findsOneWidget);
    expect(find.byType(TempoCurve), findsNothing);

    await tester.tap(find.byTooltip('Skip exercise'));
    await tester.pump();
    expect(find.text('MOVE'), findsOneWidget);
    expect(find.byType(TempoCurve), findsOneWidget);
    expect(find.byType(PhaseRing), findsNothing);
    final curve = tester.widget<TempoCurve>(find.byType(TempoCurve));
    expect((curve.moveSeconds, curve.holdSeconds, curve.returnSeconds),
        (2, 1, 2));

    // Halfway through the 2 s move = 1 s into a 5 s rep.
    await elapse(tester, 1);
    expect(tester.widget<TempoCurve>(find.byType(TempoCurve)).progress,
        closeTo(0.2, 0.05));
  });

  testWidgets('skipping past the last exercise counts as stopped',
      (tester) async {
    await pumpRunning(tester, sampleSession());
    await tester.tap(find.byTooltip('Skip exercise'));
    await tester.pump();
    await tester.tap(find.byTooltip('Skip exercise'));
    await tester.pump();
    await tester.tap(find.byTooltip('Skip exercise'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Session stopped'), findsOneWidget);
  });

  testWidgets('can go back to an exercise skipped by mistake',
      (tester) async {
    await pumpRunning(tester, sampleSession());
    await elapse(tester, 3);
    await tester.tap(find.byTooltip('Skip exercise'));
    await tester.pump();
    expect(find.text('MOVE'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous exercise'));
    await tester.pump();
    expect(find.text('MOVE'), findsNothing);
    expect(find.text('Rep 1/2'), findsOneWidget);
  });

  testWidgets('next-up names a tap set rest and the next exercise',
      (tester) async {
    await pumpRunning(
      tester,
      Session(id: 's', name: 'S', exercises: [
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
      ]),
    );
    await elapse(tester, 3);
    expect(find.text('Next: Set rest (tap)'), findsOneWidget);

    await elapse(tester, 5);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    // Last hold of A, then the transition: name B, not the transition.
    expect(find.text('Next: B'), findsOneWidget);
  });

  testWidgets('a phase change lands on the frame, not the next timer tick',
      (tester) async {
    await pumpRunning(tester, sampleSession());
    clock.advance(3);
    // A single frame, no time for the 100 ms timer to fire.
    await tester.pump();
    expect(find.text('HOLD'), findsOneWidget);
  });

  testWidgets('the header shows the upcoming exercise during a transition',
      (tester) async {
    await pumpRunning(tester, sampleSession());
    await elapse(tester, 3 + 13 + 1);
    expect(find.text('Exercise 2/2'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('a double tap on stop opens one dialog', (tester) async {
    await pumpRunning(tester, sampleSession());
    await tester.tap(find.byTooltip('Stop'));
    await tester.tap(find.byTooltip('Stop'), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Stop session?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Stop session?'), findsNothing);
  });

  testWidgets('the last frame stays up while the summary slides in',
      (tester) async {
    await pumpRunning(tester, sampleSession());
    for (final seconds in [3, 13, 10, 5]) {
      await elapse(tester, seconds);
    }
    // Mid-transition: the running screen is still drawn underneath.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(SummaryScreen), findsOneWidget);
    expect(find.text('Exercise 2/2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Session complete'), findsOneWidget);
  });

  testWidgets('keeps the screen awake and cues phases; toggles mute',
      (tester) async {
    await pumpRunning(tester, sampleSession());
    expect(cues.keepAwake, isTrue);
    expect(cues.played, [Cue.getReady]);

    await elapse(tester, 3);
    expect(cues.played.last, Cue.hold1);

    await tester.tap(find.byTooltip('Mute sounds'));
    await tester.pump();
    await elapse(tester, 5);
    // Muted: the rest started with a vibration but no sound.
    expect(cues.played.last, isNot(Cue.rest));
    expect(cues.vibrated.last, Cue.rest);
    expect(find.byTooltip('Unmute sounds'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Stop').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(cues.keepAwake, isFalse);
  });

  testWidgets('hides the vibration toggle where there is no vibrator',
      (tester) async {
    await pumpRunning(tester, sampleSession());
    expect(find.byTooltip('Turn off vibration'), findsOneWidget);
    cues.vibrationAvailable.value = false;
    await tester.pump();
    expect(find.byTooltip('Turn off vibration'), findsNothing);
    expect(find.byTooltip('Mute sounds'), findsOneWidget);
  });

  testWidgets('a finished run is recorded in the history', (tester) async {
    await pumpRunning(tester, sampleSession());
    final history =
        AppScope.read(tester.element(find.byType(RunningScreen))).history;
    await elapse(tester, 3 + 13 + 10 + 5);
    await tester.pump(const Duration(seconds: 1));

    final entry = history.entries.single;
    expect(entry.sessionId, 's');
    expect(entry.sessionName, 'S');
    expect(entry.completed, isTrue);
    expect(entry.activeTime.inSeconds, 31);
    expect(entry.endedAt, DateTime(2026, 3, 10, 9, 41, 31));
  });

  testWidgets('a run stopped before anything was done is not recorded',
      (tester) async {
    await pumpRunning(tester, sampleSession());
    final history =
        AppScope.read(tester.element(find.byType(RunningScreen))).history;
    await tester.tap(find.byTooltip('Stop'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Stop').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Session stopped'), findsOneWidget);
    expect(history.entries, isEmpty);
  });

  testWidgets('a run stopped part way is recorded as stopped', (tester) async {
    await pumpRunning(tester, sampleSession());
    final history =
        AppScope.read(tester.element(find.byType(RunningScreen))).history;
    await elapse(tester, 9); // first hold done
    await tester.tap(find.byTooltip('Stop'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Stop').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final entry = history.entries.single;
    expect(entry.completed, isFalse);
    expect((entry.reps, entry.holds), (1, 1));
  });

  testWidgets('runs a background session that follows the phases',
      (tester) async {
    await pumpRunning(
        tester, sampleSession(transition: const Transition.tap()));
    expect(background.running, isTrue);
    expect(background.shown, ['Get ready']);

    await elapse(tester, 3);
    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Resume'));
    await tester.pump();
    for (final seconds in [5, 3, 5]) {
      await elapse(tester, seconds);
    }
    expect(background.shown, [
      'Get ready',
      'Hold · Rep 1/2 · A',
      'Paused · Hold · Rep 1/2 · A',
      'Hold · Rep 1/2 · A',
      'Rest · Rep 1/2 · A',
      'Hold · Rep 2/2 · A',
      'Tap to continue · Next: B',
    ]);

    await tester.tap(find.byTooltip('Stop'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Stop').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(background.running, isFalse);
  });

  testWidgets('a tap rest between sets shows Continue and names the next set',
      (tester) async {
    await pumpRunning(
      tester,
      Session(id: 's', name: 'S', exercises: [
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
      ]),
    );
    await elapse(tester, 3);
    await elapse(tester, 5);
    expect(find.text('SET REST'), findsOneWidget);
    expect(find.text('Tap when ready'), findsOneWidget);
    expect(background.shown.last, 'Tap to continue · Next: Set 2/2 · A');

    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('HOLD'), findsOneWidget);
    expect(find.text('Set 2/2'), findsOneWidget);
  });

  testWidgets('the notification button pauses, resumes and continues',
      (tester) async {
    await pumpRunning(
        tester, sampleSession(transition: const Transition.tap()));
    await elapse(tester, 3);
    expect(background.last!.action, 'Pause');
    expect(background.last!.endsAt, isNotNull);

    background.tapAction();
    await tester.pump();
    expect(find.bySemanticsLabel('Resume'), findsOneWidget);
    expect(background.last!.text, 'Paused · Hold · Rep 1/2 · A');
    expect(background.last!.action, 'Resume');
    // Nothing to count down: no countdown, so no wake lock either.
    expect(background.last!.endsAt, isNull);

    background.tapAction();
    await tester.pump();
    expect(background.last!.action, 'Pause');
    for (final seconds in [5, 3, 5]) {
      await elapse(tester, seconds);
    }
    expect(background.last!.text, 'Tap to continue · Next: B');
    expect(background.last!.action, 'Continue');
    expect(background.last!.endsAt, isNull);

    background.tapAction();
    await tester.pump();
    expect(background.last!.action, 'Pause');
    expect(background.last!.text, isNot(startsWith('Tap to continue')));
  });

  testWidgets('an out-of-date notification button does nothing',
      (tester) async {
    await pumpRunning(
        tester, sampleSession(transition: const Transition.tap()));
    await elapse(tester, 3);
    // Paused on screen, but the notification still says "Pause": tapping it
    // must not resume.
    await tester.tap(find.bySemanticsLabel('Pause'));
    await tester.pump();
    expect(background.last!.action, 'Resume');
    background.tapLabel('Pause');
    await tester.pump();
    expect(find.bySemanticsLabel('Resume'), findsOneWidget);

    // Waiting for a tap, but the notification still says "Resume" or
    // "Pause": the wait isn't skipped.
    background.tapAction();
    await tester.pump();
    for (final seconds in [5, 3, 5]) {
      await elapse(tester, seconds);
    }
    expect(background.last!.action, 'Continue');
    background.tapLabel('Pause');
    background.tapLabel('Resume');
    await tester.pump();
    expect(background.last!.action, 'Continue');
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('swiping the app away ends the session', (tester) async {
    await pumpRunning(tester, sampleSession());
    await elapse(tester, 3);
    background.dismiss();
    await tester.pump();
    expect(background.running, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(SummaryScreen), findsOneWidget);
  });

  testWidgets(
      'on resume: keeps the screen awake again, resyncs the notification '
      'and retries a refused start', (tester) async {
    await pumpRunning(tester, sampleSession());
    await elapse(tester, 3);
    // E.g. the activity was recreated without the keep-awake flag.
    cues.keepAwake = false;
    final endsAt = background.last!.endsAt!;
    final updates = background.updates;
    // The wall clock was set forward while the app was away: the runner
    // (on its own clock) changes nothing, but the countdown is off.
    wallClockFrozenAt = clock.now + const Duration(seconds: 5);
    wallClockFrozen = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(cues.keepAwake, isTrue);
    expect(background.ensureStartedCalls, 1);
    expect(background.updates, updates + 1);
    expect(background.last!.endsAt!.difference(endsAt),
        const Duration(seconds: 5));
  });

  testWidgets('the notification button does nothing behind the stop dialog',
      (tester) async {
    await pumpRunning(tester, sampleSession());
    await elapse(tester, 3);
    await tester.tap(find.byTooltip('Stop'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Stop session?'), findsOneWidget);
    expect(background.last!.text, 'Paused · Hold · Rep 1/2 · A');
    // No button while the dialog is up, and a tap racing that is ignored.
    expect(background.last!.action, isNull);
    background.tapLabel('Pause');
    await tester.pump();
    expect(background.last!.text, 'Paused · Hold · Rep 1/2 · A');

    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(background.last!.action, 'Pause');
    expect(background.last!.text, isNot(startsWith('Paused')));
  });

  testWidgets('cancelling the stop dialog while paused brings the button back',
      (tester) async {
    await pumpRunning(tester, sampleSession());
    await elapse(tester, 3);
    background.tapAction();
    await tester.pump();
    expect(background.last!.action, 'Resume');

    await tester.tap(find.byTooltip('Stop'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(background.last!.action, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(background.last!.action, 'Resume');
  });

  testWidgets('stops the background session as soon as the session ends',
      (tester) async {
    await pumpRunning(
      tester,
      Session(id: 's', name: 'S', exercises: [
        const HoldExercise(
          id: 'a',
          name: 'A',
          sets: 1,
          restBetweenSets: 0,
          tapBetweenSets: false,
          reps: 1,
          holdSeconds: 5,
          restBetweenReps: 0,
        ),
      ]),
    );
    await elapse(tester, 3);
    expect(background.running, isTrue);
    await elapse(tester, 5);
    // The summary route is still coming in, so this screen isn't disposed
    // yet (in the background it wouldn't be until the app is reopened).
    expect(find.byType(RunningScreen), findsOneWidget);
    expect(background.running, isFalse);
    await tester.pumpAndSettle();
    expect(find.byType(SummaryScreen), findsOneWidget);
  });

  testWidgets('resends the countdown when it drifts from the timer',
      (tester) async {
    await pumpRunning(
      tester,
      Session(id: 's', name: 'S', exercises: [
        const HoldExercise(
          id: 'a',
          name: 'A',
          sets: 1,
          restBetweenSets: 0,
          tapBetweenSets: false,
          reps: 1,
          holdSeconds: 10,
          restBetweenReps: 0,
        ),
      ]),
    );
    await elapse(tester, 3);
    final endsAt = background.last!.endsAt!;
    // Counting down with both clocks in step resends nothing.
    final updates = background.updates;
    await elapse(tester, 1);
    expect(background.updates, updates);
    expect(background.last!.endsAt, endsAt);
    // The runner's clock moves on but the wall clock doesn't (as when the
    // wall clock is set back): the countdown has to follow the timer.
    wallClockFrozenAt = clock.now;
    wallClockFrozen = true;
    await elapse(tester, 4);
    expect(find.text('HOLD'), findsOneWidget);
    expect(
      endsAt.difference(background.last!.endsAt!),
      greaterThan(const Duration(seconds: 3)),
    );
    expect(background.shown.last, startsWith('Hold · '));
  });

  testWidgets('going back an exercise updates the notification',
      (tester) async {
    await pumpRunning(tester, sampleSession());
    await elapse(tester, 3);
    await tester.tap(find.byTooltip('Skip exercise'));
    await tester.pump();
    expect(background.last!.text, isNot(contains('· A')));

    await tester.tap(find.byTooltip('Previous exercise'));
    await tester.pump();
    expect(background.last!.text, 'Hold · Rep 1/2 · A');
  });
  testWidgets('the notification names the set, and the set coming up in a '
      'timed set rest', (tester) async {
    await pumpRunning(
      tester,
      Session(id: 's', name: 'S', exercises: [
        const HoldExercise(
          id: 'a',
          name: 'A',
          sets: 3,
          restBetweenSets: 30,
          tapBetweenSets: false,
          reps: 1,
          holdSeconds: 5,
          restBetweenReps: 0,
        ),
      ]),
    );
    await elapse(tester, 3);
    expect(background.last!.text, 'Hold · Set 1/3 · Rep 1/1 · A');
    await elapse(tester, 5);
    expect(background.last!.text, 'Set rest · Next: Set 2/3 · A');
    await elapse(tester, 30);
    expect(background.last!.text, 'Hold · Set 2/3 · Rep 1/1 · A');
  });

  testWidgets('opening the stop dialog updates the notification once',
      (tester) async {
    await pumpRunning(tester, sampleSession());
    await elapse(tester, 3);
    final updates = background.updates;
    await tester.tap(find.byTooltip('Stop'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(background.last!.action, isNull);
    expect(background.updates, updates + 1);
  });
}
