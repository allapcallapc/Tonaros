import 'package:flutter_test/flutter_test.dart';
import 'package:tonaros/models/session.dart';

void main() {
  // Also run on the web (flutter test --platform chrome): newId once
  // threw there because `1 << 32` is 0 in JavaScript.
  test('newId returns distinct ids', () {
    final ids = {for (var i = 0; i < 100; i++) newId()};
    expect(ids, hasLength(100));
  });

  test('a duplicated session gets fresh ids throughout', () {
    final session = Session(
      id: 's',
      name: 'S',
      exercises: [HoldExercise.blank(), TempoExercise.blank()],
    );
    final copy = session.duplicate('S (copy)');
    expect(copy.id, isNot(session.id));
    for (var i = 0; i < 2; i++) {
      expect(copy.exercises[i].id, isNot(session.exercises[i].id));
      expect(copy.exercises[i].runtimeType, session.exercises[i].runtimeType);
    }
  });
}
