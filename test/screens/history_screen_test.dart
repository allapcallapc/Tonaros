import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonaros/app_scope.dart';
import 'package:tonaros/screens/history_screen.dart';
import 'package:tonaros/services/history_store.dart';

import '../models/history_entry_test.dart' show run;
import '../test_app.dart';

void main() {
  final now = DateTime(2026, 3, 10, 18);

  Future<HistoryStore> pumpHistory(WidgetTester tester,
      {String? sessionId}) async {
    // A phone-sized screen, so the runs below the calendar are on screen.
    tester.view.physicalSize = const Size(1200, 2700);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await withAppScope(MaterialApp(
      home:
          HistoryScreen(sessionId: sessionId, sessionName: 'S', now: () => now),
    )));
    return AppScope.read(tester.element(find.byType(HistoryScreen))).history;
  }

  testWidgets('empty state', (tester) async {
    await pumpHistory(tester);
    expect(find.text('No runs yet'), findsOneWidget);
  });

  testWidgets('streaks, calendar and runs by day', (tester) async {
    final history = await pumpHistory(tester);
    await history.add(run(DateTime(2026, 3, 9, 8, 5)));
    await history.add(run(DateTime(2026, 3, 10, 9, 30), completed: false));
    await history.add(run(DateTime(2026, 3, 2, 7), sessionId: 'x'));
    await tester.pumpAndSettle();

    expect(find.text('2 days'), findsNWidgets(2)); // current and best
    expect(find.text('March 2026'), findsOneWidget);
    expect(find.text('Tue 10 March'), findsOneWidget);
    expect(find.text('Mon 9 March'), findsOneWidget);
    expect(find.textContaining('09:30 · Stopped'), findsOneWidget);

    // Tapping a day in the calendar shows only that day's runs.
    await tester.tap(find.text('9'));
    await tester.pumpAndSettle();
    expect(find.text('Tue 10 March'), findsNothing);
    expect(find.text('Mon 9 March'), findsNWidgets(2)); // chip + header
    await tester.tap(find.byTooltip('Show all days'));
    await tester.pumpAndSettle();
    expect(find.text('Tue 10 March'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('February 2026'), findsOneWidget);
  });

  testWidgets('only one session\'s runs', (tester) async {
    final history = await pumpHistory(tester, sessionId: 's');
    await history.add(run(DateTime(2026, 3, 10, 8)));
    await history.add(run(DateTime(2026, 3, 10, 9), sessionId: 'x'));
    await tester.pumpAndSettle();

    expect(find.text('History · S'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
  });

  testWidgets('delete a run, undo, then clear', (tester) async {
    final history = await pumpHistory(tester);
    await history.add(run(DateTime(2026, 3, 10, 8)));
    await history.add(run(DateTime(2026, 3, 9, 8)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete run').first);
    await tester.pumpAndSettle();
    expect(history.entries, hasLength(1));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(history.entries, hasLength(2));

    await tester.tap(find.byTooltip('Clear history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(history.entries, isEmpty);
    expect(find.text('No runs yet'), findsOneWidget);
  });
}
