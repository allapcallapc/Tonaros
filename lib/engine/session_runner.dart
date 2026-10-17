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

/// Time elapsed on a monotonic clock, from an arbitrary origin.
typedef MonotonicClock = Duration Function();

/// A [MonotonicClock] backed by a [Stopwatch]: unlike `DateTime.now`, it
/// doesn't jump when the system time is adjusted (NTP sync, manual change).
MonotonicClock stopwatchClock() {
  final stopwatch = Stopwatch()..start();
  return () => stopwatch.elapsed;
}

/// Runs a session's phases against a monotonic clock: every phase ends at a
/// fixed instant, so timing doesn't drift and stays right after time in the
/// background - the next [tick] catches up through every phase that ended
/// meanwhile. (On Android the background service holds a wake lock while a
/// session runs, so the monotonic clock keeps advancing with the screen
/// off.)
class SessionRunner extends ChangeNotifier {
  SessionRunner(this.session, {MonotonicClock? clock})
      : plan = buildPlan(session),
        _clock = clock ?? stopwatchClock();

  final Session session;
  final List<Phase> plan;
  final MonotonicClock _clock;

  final _events = StreamController<RunnerEvent>.broadcast(sync: true);

  /// Phase changes, second ticks and the end of the session. Delivered
  /// synchronously, in the middle of the state change that caused them, so
  /// a listener must not call back into the runner (skip, pause, stop...)
  /// from its handler: that would re-enter the controller while it fires.
  /// React through [notifyListeners] or a later microtask instead.
  Stream<RunnerEvent> get events => _events.stream;

  RunnerStatus get status => _status;
  RunnerStatus _status = RunnerStatus.paused;
  bool _started = false;

  int get index => _index;
  int _index = 0;

  Phase get phase => plan[_index];
  Phase? get nextPhase => _index + 1 < plan.length ? plan[_index + 1] : null;
  Exercise get exercise => session.exercises[phase.exerciseIndex];

  /// The exercise to show for the current phase: its own, or for a
  /// transition between exercises, the one coming next.
  int get displayExerciseIndex {
    if (phase.kind != PhaseKind.transition &&
        phase.kind != PhaseKind.waitForTap) {
      return phase.exerciseIndex;
    }
    for (var i = _index + 1; i < plan.length; i++) {
      final p = plan[i];
      if (p.kind != PhaseKind.transition && p.kind != PhaseKind.waitForTap) {
        return p.exerciseIndex;
      }
    }
    return phase.exerciseIndex;
  }

  /// When the current phase ends on [_clock], while running.
  Duration? _phaseEnd;

  /// Time left in the current phase while paused (or before start).
  Duration _remainingWhenPaused = Duration.zero;

  /// Time spent running, pauses excluded, up to [_runningSince].
  Duration _activeBefore = Duration.zero;
  Duration? _runningSince;

  int _lastSecondsLeft = -1;

  /// Fires [tick] while running; cancelled otherwise, so a paused or
  /// tap-waiting session doesn't wake the isolate 10 times a second.
  Timer? _timer;

  @visibleForTesting
  bool get isTimerRunning => _timer?.isActive ?? false;

  /// True once the last phase ended on its own - not skipped past or
  /// stopped.
  bool get completed => _completed;
  bool _completed = false;

  /// Set when a phase was skipped to while paused: [resume] announces it.
  bool _announceOnResume = false;

  /// Holds and reps completed so far (skipped ones don't count).
  int get holdsDone => _holdsDone;
  int _holdsDone = 0;
  int get repsDone => _repsDone;
  int _repsDone = 0;

  Duration get remaining => switch (_status) {
        RunnerStatus.running => _nonNegative(_phaseEnd! - _clock()),
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
      (_runningSince == null ? Duration.zero : _clock() - _runningSince!);

  /// Starts with the get-ready phase. Subscribe to [events] before calling
  /// this: its first [PhaseStarted] is sent synchronously, from here.
  void start() {
    if (_started || plan.isEmpty) return;
    _started = true;
    _index = 0;
    _startPhase(_clock(), announce: true);
  }

  void pause() {
    // A phase whose end has already passed advances first, rather than
    // being frozen at 0 and losing the time since its real end.
    tick();
    if (_status != RunnerStatus.running) return;
    _remainingWhenPaused = remaining;
    _stopActiveClock();
    _setStatus(RunnerStatus.paused);
    notifyListeners();
  }

  void resume() {
    if (_status != RunnerStatus.paused || !_started) return;
    final now = _clock();
    _phaseEnd = now + _remainingWhenPaused;
    _runningSince = now;
    _setStatus(RunnerStatus.running);
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

  /// Skips the exercise on screen ([displayExerciseIndex] - during get
  /// ready or a transition, the one coming up) and jumps to the start of the
  /// one after it, or ends the session.
  void skipExercise() {
    if (!_started || _status == RunnerStatus.finished) return;
    final current = displayExerciseIndex;
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

  /// Advances past every phase whose end has passed. Runs on a timer while
  /// running, and can be called directly (each frame by the running screen,
  /// or when the app returns to the foreground).
  void tick() {
    if (_status != RunnerStatus.running) return;
    final now = _clock();
    var changed = 0;
    while (_status == RunnerStatus.running && now >= _phaseEnd!) {
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
    if (wasPaused) {
      // Stay paused, at the start of the new phase.
      _remainingWhenPaused = Duration(seconds: phase.seconds);
      _lastSecondsLeft = secondsLeft;
      if (phase.waitsForTap) {
        // Nothing to resume: wait for the tap straight away.
        _setStatus(RunnerStatus.waitingForTap);
        _events.add(PhaseStarted(phase, skipped: skipped));
      } else {
        // No cue while paused; resume() announces the phase.
        _announceOnResume = true;
      }
      notifyListeners();
    } else {
      _startPhase(_clock(), announce: true, skipped: skipped);
    }
  }

  void _startPhase(Duration start,
      {required bool announce, bool skipped = false}) {
    if (phase.waitsForTap) {
      _stopActiveClock(start);
      _setStatus(RunnerStatus.waitingForTap);
      _phaseEnd = null;
    } else {
      _runningSince ??= start;
      _phaseEnd = start + Duration(seconds: phase.seconds);
      _setStatus(RunnerStatus.running);
    }
    if (announce) {
      _lastSecondsLeft = secondsLeft;
      _events.add(PhaseStarted(phase, skipped: skipped));
      notifyListeners();
    }
  }

  /// Every status change goes through here, so the timer only runs while
  /// the clock does.
  void _setStatus(RunnerStatus status) {
    _status = status;
    if (status == RunnerStatus.running) {
      _timer ??= Timer.periodic(
          const Duration(milliseconds: 100), (_) => tick());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _completePhase(Phase p) {
    if (p.isHold) _holdsDone++;
    if (p.endsRep) _repsDone++;
  }

  void _stopActiveClock([Duration? at]) {
    if (_runningSince != null) {
      _activeBefore += (at ?? _clock()) - _runningSince!;
      _runningSince = null;
    }
  }

  void _finish({required bool announce, Duration? at}) {
    _stopActiveClock(at);
    _setStatus(RunnerStatus.finished);
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
