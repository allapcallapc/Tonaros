import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tonaros/engine/session_plan.dart';
import 'package:tonaros/engine/session_runner.dart';
import 'package:tonaros/services/cues.dart';
import 'package:tonaros/services/settings_store.dart';

import '../engine/session_runner_test.dart' show FakeClock, sampleSession;
import '../test_app.dart' show FakeCueOutput;

void main() {
  late FakeClock clock;
  late SessionRunner runner;
  late FakeCueOutput output;
  late SettingsStore settings;
  late CuePlayer cues;

  Future<void> setUpCues([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    settings = SettingsStore(await SharedPreferences.getInstance());
    clock = FakeClock();
    runner = SessionRunner(sampleSession(), clock: () => clock.now);
    output = FakeCueOutput();
    cues = CuePlayer(events: runner.events, settings: settings, output: output);
  }

  /// Ticks every 100 ms, like the runner's own timer.
  void elapse(num seconds) {
    for (var i = 0; i < (seconds * 10).round(); i++) {
      clock.advance(0.1);
      runner.tick();
    }
  }

  tearDown(() async {
    await cues.dispose();
    runner.dispose();
  });

  test('a distinct cue per phase, ticks only on the last 3 s of 4 s+ phases',
      () async {
    await setUpCues();
    runner.start();
    // Get ready (3 s, no ticks) → hold 5 s (ticks at 3, 2, 1) → rest 3 s
    // (no ticks) → hold 5 s (ticks) → transition 10 s (ticks) → tempo.
    elapse(3 + 5 + 3 + 5 + 10);
    expect(output.played, [
      Cue.getReady,
      Cue.hold1, Cue.tick, Cue.tick, Cue.tick,
      Cue.rest,
      Cue.hold1, Cue.tick, Cue.tick, Cue.tick,
      Cue.transition, Cue.tick, Cue.tick, Cue.tick,
      Cue.move,
    ]);
    expect(output.vibrated, output.played);
  });

  test('ends with the finished cue', () async {
    await setUpCues();
    runner.start();
    elapse(40);
    expect(output.played.last, Cue.finished);
  });

  test('sound and vibration follow their settings', () async {
    await setUpCues({'soundOn': false});
    runner.start();
    expect(output.played, isEmpty);
    expect(output.vibrated, [Cue.getReady]);

    await settings.setSoundOn(true);
    await settings.setVibrationOn(false);
    elapse(3);
    expect(output.played, [Cue.hold1]);
    expect(output.vibrated, [Cue.getReady]);
  });

  test('every phase kind has a cue with a sound and a pattern', () async {
    await setUpCues();
    for (final kind in PhaseKind.values) {
      final cue = Cue.forPhase(kind);
      expect(cue.sound, isNotEmpty);
      expect(cue.vibration.length.isEven, isTrue);
    }
    // All phase cues are distinct.
    expect(PhaseKind.values.map(Cue.forPhase).toSet().length,
        PhaseKind.values.length);
  });
}
