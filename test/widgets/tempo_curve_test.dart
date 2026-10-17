import 'package:flutter_test/flutter_test.dart';
import 'package:tonaros/widgets/tempo_curve.dart';

void main() {
  double at(int segment, double done, {int hold = 1}) => TempoCurve.progressAt(
        segment: segment,
        fractionDone: done,
        moveSeconds: 3,
        holdSeconds: hold,
        returnSeconds: 2,
      );

  test('progress is by time across move, hold and return', () {
    expect(at(0, 0), 0);
    expect(at(0, 1), closeTo(3 / 6, 1e-9));
    expect(at(1, 0.5), closeTo(3.5 / 6, 1e-9));
    expect(at(2, 1), 1);
  });

  test('a 0 s hold takes no time', () {
    expect(at(0, 1, hold: 0), closeTo(3 / 5, 1e-9));
    expect(at(2, 0, hold: 0), closeTo(3 / 5, 1e-9));
  });
}
