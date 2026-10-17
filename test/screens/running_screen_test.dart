import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonaros/models/session.dart';
import 'package:tonaros/screens/running_screen.dart';
import 'package:tonaros/screens/summary_screen.dart';
import 'package:tonaros/widgets/rep_dots.dart';

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
}
