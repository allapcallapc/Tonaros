import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/session.dart';
import 'session_plan.dart';

enum RunnerStatus { running, paused, waitingForTap, finished }

/// Something cues (sound, vibration) react to.
sealed class RunnerEvent {
  const RunnerEvent();
}

/// A new phase started. [skipped] is set when it started because the user
/// skipped ahead; [caughtUp] when several phases ended at once (e.g. after
/// time in the background) and this is the one now running.
class PhaseStarted extends RunnerEvent {
  const PhaseStarted(this.phase, {this.skipped = false, this.caughtUp = false});

  final Phase phase;
  final bool skipped;
  final bool caughtUp;
}

/// Whole seconds left in the current phase changed.
class SecondsLeftChanged extends RunnerEvent {
  const SecondsLeftChanged(this.phase, this.secondsLeft);

  final Phase phase;
  final int secondsLeft;
}

class SessionFinished extends RunnerEvent {
  const SessionFinished();
}

/// Runs a session's phases against the wall clock: every phase ends at a
/// fixed instant, so timing doesn't drift and stays right after time in
/// the background - the next [tick] catches up through every phase that
/// ended meanwhile.
class SessionRunner extends ChangeNotifier {
  SessionRunner(this.session, {DateTime Function()? clock})
      : plan = buildPlan(session),
        _clock = clock ?? DateTime.now;

  final Session session;
  final List<Phase> plan;
  final DateTime Function() _clock;

  final _events = StreamController<RunnerEvent>.broadcast(sync: true);

  /// Phase changes, second ticks and the end of the session.
  Stream<RunnerEvent> get events => _events.stream;

  RunnerStatus get status => _status;
  RunnerStatus _status = RunnerStatus.paused;
  bool _started = false;

  int get index => _index;
  int _index = 0;

  Phase get phase => plan[_index];
  Phase? get nextPhase => _index + 1 < plan.length ? plan[_index + 1] : null;
  Exercise get exercise => session.exercises[phase.exerciseIndex];

  /// When the current phase ends, while running.
  DateTime? _phaseEnd;

  /// Time left in the current phase while paused (or before start).
  Duration _remainingWhenPaused = Duration.zero;

  /// Wall time spent running, pauses excluded, up to [_runningSince].
  Duration _activeBefore = Duration.zero;
  DateTime? _runningSince;

  int _lastSecondsLeft = -1;
  Timer? _timer;

  /// True once the last phase ended on its own - not skipped past or
  /// stopped.
  bool get completed => _completed;
  bool _completed = false;

  /// Set when a phase was skipped to while paused: [resume] announces it.
  bool _announceOnResume = false;

  int holdsDone = 0;
  int repsDone = 0;

  Duration get remaining => switch (_status) {
        RunnerStatus.running => _nonNegative(_phaseEnd!.difference(_clock())),
        RunnerStatus.paused => _remainingWhenPaused,
        _ => Duration.zero,
      };

  /// Whole seconds shown on screen: 4.2 s left reads "5".
  int get secondsLeft => (remaining.inMilliseconds / 1000).ceil();

  /// 1 at the start of a phase, 0 at its end.
  double get fractionLeft => phase.seconds == 0
      ? 1
      : (remaining.inMilliseconds / (phase.seconds * 1000)).clamp(0.0, 1.0);

  Duration get activeTime =>
      _activeBefore +
      (_runningSince == null ? Duration.zero : _clock().difference(_runningSince!));

  /// Starts with the get-ready phase. Subscribe to [events] before calling
  /// this: its first [PhaseStarted] is sent synchronously, from here.
  void start() {
    if (_started || plan.isEmpty) return;
    _started = true;
    _enterPhase(0, _clock());
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => tick());
  }

  void pause() {
    if (_status != RunnerStatus.running) return;
    _remainingWhenPaused = remaining;
    _stopActiveClock();
    _status = RunnerStatus.paused;
    notifyListeners();
  }

  void resume() {
    if (_status != RunnerStatus.paused || !_started) return;
    final now = _clock();
    _phaseEnd = now.add(_remainingWhenPaused);
    _runningSince = now;
    _status = RunnerStatus.running;
    if (_announceOnResume) {
      // Skipped while paused: announce the phase now that it runs.
      _announceOnResume = false;
      _events.add(PhaseStarted(phase, skipped: true));
    }
    notifyListeners();
  }

  void togglePause() =>
      _status == RunnerStatus.running ? pause() : resume();

  /// Ends the current phase now. Also how a "wait until tap" phase (a
  /// transition or a tap rest between sets) is dismissed.
  void skipPhase() {
    if (!_started || _status == RunnerStatus.finished) return;
    _moveTo(_index + 1, skipped: true);
  }

  /// Jumps to the start of the next exercise (or ends the session).
  void skipExercise() {
    if (!_started || _status == RunnerStatus.finished) return;
    final current = phase.kind == PhaseKind.getReady ? -1 : phase.exerciseIndex;
    var next = _index + 1;
    while (next < plan.length &&
        (plan[next].exerciseIndex <= current ||
            plan[next].kind == PhaseKind.transition ||
            plan[next].kind == PhaseKind.waitForTap)) {
      next++;
    }
    _moveTo(next, skipped: true);
  }

  /// Ends the session early.
  void stop() {
    if (_status == RunnerStatus.finished) return;
    _finish(announce: false);
  }

  /// Advances past every phase whose end has passed. Runs on a timer, and
  /// can be called directly (e.g. when the app returns to the foreground).
  void tick() {
    if (_status != RunnerStatus.running) return;
    final now = _clock();
    var changed = 0;
    while (_status == RunnerStatus.running && !now.isBefore(_phaseEnd!)) {
      _completePhase(phase);
      final boundary = _phaseEnd!;
      if (_index + 1 >= plan.length) {
        _completed = true;
        _finish(announce: true, at: boundary);
        return;
      }
      _index++;
      changed++;
      // Start from the exact boundary rather than "now", so no time is lost
      // to timer granularity.
      _startPhase(boundary, announce: false);
    }
    if (changed > 0) {
      _lastSecondsLeft = secondsLeft;
      _events.add(PhaseStarted(phase, caughtUp: changed > 1));
      notifyListeners();
    } else if (secondsLeft != _lastSecondsLeft) {
      _lastSecondsLeft = secondsLeft;
      _events.add(SecondsLeftChanged(phase, _lastSecondsLeft));
      notifyListeners();
    }
  }

  void _moveTo(int index, {required bool skipped}) {
    if (index >= plan.length) {
      // Skipped past the end: stopped early, no "finished" fanfare.
      _finish(announce: false);
      return;
    }
    final wasPaused = _status == RunnerStatus.paused;
    _announceOnResume = false;
    _index = index;
    final now = _clock();
    if (wasPaused) {
      // Stay paused, at the start of the new phase.
      _remainingWhenPaused = Duration(seconds: phase.seconds);
      _lastSecondsLeft = secondsLeft;
      if (phase.waitsForTap) {
        // Nothing to resume: wait for the tap straight away.
        _status = RunnerStatus.waitingForTap;
        _events.add(PhaseStarted(phase, skipped: skipped));
      } else {
        // No cue while paused; resume() announces the phase.
        _announceOnResume = true;
      }
      notifyListeners();
    } else {
      _startPhase(now, announce: true, skipped: skipped);
    }
  }

  void _enterPhase(int index, DateTime now) {
    _index = index;
    _startPhase(now, announce: true);
  }

  void _startPhase(DateTime start, {required bool announce, bool skipped = false}) {
    if (phase.waitsForTap) {
      _stopActiveClock(start);
      _status = RunnerStatus.waitingForTap;
      _phaseEnd = null;
    } else {
      _runningSince ??= start;
      _status = RunnerStatus.running;
      _phaseEnd = start.add(Duration(seconds: phase.seconds));
    }
    if (announce) {
      _lastSecondsLeft = secondsLeft;
      _events.add(PhaseStarted(phase, skipped: skipped));
      notifyListeners();
    }
  }

  void _completePhase(Phase p) {
    if (p.isHold) holdsDone++;
    if (p.endsRep) repsDone++;
  }

  void _stopActiveClock([DateTime? at]) {
    if (_runningSince != null) {
      _activeBefore += (at ?? _clock()).difference(_runningSince!);
      _runningSince = null;
    }
  }

  void _finish({required bool announce, DateTime? at}) {
    _stopActiveClock(at);
    _timer?.cancel();
    _status = RunnerStatus.finished;
    if (announce) _events.add(const SessionFinished());
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _events.close();
    super.dispose();
  }

  static Duration _nonNegative(Duration d) => d.isNegative ? Duration.zero : d;
}
