import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tonaros/models/session.dart';

import '../test_app.dart';

Future<void> enterDialogText(WidgetTester tester, String text, String button) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.text(button));
  await tester.pumpAndSettle();
}

Future<void> openMenu(WidgetTester tester, String item, {int index = 0}) async {
  await tester.tap(find.byTooltip('More').at(index));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('create a session, add a hold and a tempo exercise',
      (tester) async {
    final store = await pumpApp(tester);
    expect(find.text('No sessions yet'), findsOneWidget);

    await tester.tap(find.text('New session'));
    await tester.pumpAndSettle();
    await enterDialogText(tester, 'Knee', 'Create');

    // Straight into the editor.
    expect(find.text('No exercises yet.\nAdd one to build this session.'),
        findsOneWidget);

    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hold'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Quad set');
    await tester.tap(find.byTooltip('Decrease Reps'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Quad set'), findsOneWidget);
    expect(find.text('1 set × 9 reps · hold 5 s · rest 5 s'), findsOneWidget);

    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tempo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Unnamed falls back to the type name; a transition now sits between.
    expect(find.text('Tempo exercise'), findsOneWidget);
    expect(find.text('10 s countdown'), findsOneWidget);
    // 3 get ready + 9×5 hold + 8×5 rest + 10 transition + 10×7 tempo.
    expect(find.text('≈ 2 min 48 s'), findsOneWidget);

    final saved = store.sessions.single;
    expect(saved.name, 'Knee');
    expect(saved.exercises.map((e) => e.runtimeType),
        [HoldExercise, TempoExercise]);
  });

  testWidgets('change a transition to "wait for tap"', (tester) async {
    final store = await pumpApp(tester);
    final s = await store.create('S');
    await store.update(s.copyWith(exercises: [
      HoldExercise.blank().copyWith(name: 'A'),
      HoldExercise.blank().copyWith(name: 'B'),
    ]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('S'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('10 s countdown'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wait for tap').last);
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(store.sessions.single.exercises.first.transition,
        const Transition.tap());
    expect(find.textContaining('+ 1 tap'), findsOneWidget);
  });

  testWidgets('remove an exercise, then undo', (tester) async {
    final store = await pumpApp(tester);
    final s = await store.create('S');
    await store.update(s.copyWith(exercises: [
      HoldExercise.blank().copyWith(name: 'A'),
      HoldExercise.blank().copyWith(name: 'B'),
    ]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('S'));
    await tester.pumpAndSettle();

    await openMenu(tester, 'Remove');
    expect(store.sessions.single.exercises.map((e) => e.name), ['B']);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(store.sessions.single.exercises.map((e) => e.name), ['A', 'B']);
  });

  testWidgets('rename, duplicate and delete sessions from the list',
      (tester) async {
    final store = await pumpApp(tester);
    await store.create('Morning');
    await tester.pumpAndSettle();

    await openMenu(tester, 'Rename');
    await enterDialogText(tester, 'Evening', 'Rename');
    expect(find.text('Evening'), findsOneWidget);

    await openMenu(tester, 'Duplicate');
    expect(find.text('Evening (copy)'), findsOneWidget);

    await openMenu(tester, 'Delete', index: 1);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(store.sessions.map((s) => s.name), ['Evening']);
  });
}
