import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonaros/models/session.dart';
import 'package:tonaros/screens/running_screen.dart';
import 'package:tonaros/screens/summary_screen.dart';
import 'package:tonaros/widgets/phase_ring.dart';
import 'package:tonaros/widgets/rep_dots.dart';
import 'package:tonaros/widgets/tempo_curve.dart';

import '../engine/session_runner_test.dart' show FakeClock, sampleSession;

void main() {
  late FakeClock clock;

  Future<void> pumpRunning(WidgetTester tester, Session session) async {
    clock = FakeClock();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  RunningScreen(session: session, clock: () => clock.now),
            ),
          ),
          child: const Text('go'),
        ),
      ),
    ));
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
}
