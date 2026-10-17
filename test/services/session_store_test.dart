import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tonaros/models/session.dart';
import 'package:tonaros/services/session_store.dart';

void main() {
  Future<SessionStore> store([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    return SessionStore(await SharedPreferences.getInstance());
  }

  test('sessions survive a reload, exercises and transitions included',
      () async {
    final first = await store();
    final session = await first.create('Morning');
    await first.update(session.copyWith(exercises: [
      HoldExercise.blank().copyWith(
        name: 'Plank',
        twoHolds: true,
        tapBetweenSets: true,
        firstHoldName: 'Up',
        transition: const Transition.tap(),
      ),
      TempoExercise.blank().copyWith(name: 'Squat', holdSeconds: 0),
    ]));

    final reloaded =
        SessionStore(await SharedPreferences.getInstance()).sessions.single;
    expect(reloaded.name, 'Morning');
    final [plank as HoldExercise, squat as TempoExercise] = reloaded.exercises;
    expect(plank.twoHolds, isTrue);
    expect(plank.tapBetweenSets, isTrue);
    expect(squat.tapBetweenSets, isFalse);
    expect(plank.firstHoldName, 'Up');
    expect(plank.transition, const Transition.tap());
    expect(squat.name, 'Squat');
    expect(squat.holdSeconds, 0);
  });

  test('duplicate inserts an independent copy after the original', () async {
    final s = await store();
    final a = await s.create('A');
    await s.update(a.copyWith(exercises: [HoldExercise.blank()]));
    await s.create('B');

    final copy = await s.duplicate(s.byId(a.id)!);

    expect(s.sessions.map((x) => x.name), ['A', 'A (copy)', 'B']);
    expect(copy.id, isNot(a.id));
    expect(copy.exercises.single.id, isNot(s.byId(a.id)!.exercises.single.id));
  });

  test('rename and delete', () async {
    final s = await store();
    final a = await s.create('A');
    await s.update(a.copyWith(name: 'Renamed'));
    expect(s.sessions.single.name, 'Renamed');
    await s.delete(a.id);
    expect(s.sessions, isEmpty);
  });

  Iterable<String> backups(SharedPreferences prefs) => [
        for (final k in prefs.getKeys())
          if (k.startsWith('sessions.corrupt.')) prefs.getString(k)!,
      ];

  test('unreadable saved data starts empty and keeps a backup', () async {
    final s = await store({'sessions': 'not json'});
    expect(s.sessions, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(backups(prefs), ['not json']);

    // Backed up once, not again on every launch.
    SessionStore(prefs);
    expect(backups(prefs), hasLength(1));
  });

  test('one unreadable session does not lose the others', () async {
    final good = Session(id: 'a', name: 'Good', exercises: [
      HoldExercise.blank(),
    ]);
    const bad = {'id': 'b', 'name': 'Bad', 'exercises': 'nope'};
    final s = await store({
      'sessions': jsonEncode([good.toJson(), bad]),
    });

    expect(s.sessions.map((x) => x.name), ['Good']);
    final prefs = await SharedPreferences.getInstance();
    expect(backups(prefs).map(jsonDecode), [
      [bad],
    ]);
    expect(SessionStore(prefs).sessions.map((x) => x.name), ['Good']);
    expect(backups(prefs), hasLength(1));
  });
}
