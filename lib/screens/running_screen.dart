import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_scope.dart';
import '../engine/session_plan.dart';
import '../engine/session_runner.dart';
import '../models/history_entry.dart';
import '../models/session.dart';
import '../services/background_session.dart';
import '../services/cues.dart';
import '../services/settings_store.dart';
import '../theme/phase_colors.dart';
import '../widgets/dialogs.dart';
import '../widgets/phase_ring.dart';
import '../widgets/rep_dots.dart';
import '../widgets/session_progress_bar.dart';
import '../widgets/tempo_curve.dart';
import 'summary_screen.dart';

/// Runs a session: 3 s get ready, then every exercise and transition.
class RunningScreen extends StatefulWidget {
  const RunningScreen({
    super.key,
    required this.session,
    this.clock,
    this.now,
    this.cueOutput,
    this.background,
  });

  final Session session;

  /// Injectable for tests.
  final MonotonicClock? clock;

  /// Wall-clock time, for when a run is recorded in the history. Injectable
  /// for tests.
  final DateTime Function()? now;

  /// Defaults to the app-wide [AppScope.cues].
  final CueOutput? cueOutput;

  /// Defaults to one from [AppScope.backgroundSession].
  final BackgroundSession? background;

  @override
  State<RunningScreen> createState() => _RunningScreenState();

  /// Opens the running screen for [session] (if it has any exercises).
  static void open(BuildContext context, Session session) {
    if (session.exercises.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RunningScreen(session: session)),
    );
  }
}

class _RunningScreenState extends State<RunningScreen>
    with WidgetsBindingObserver {
  late final SessionRunner _runner =
      SessionRunner(widget.session, clock: widget.clock);
  late final CueOutput _cueOutput =
      widget.cueOutput ?? AppScope.read(context).cues;
  late final CuePlayer _cues;
  late final BackgroundSession _background =
      widget.background ?? AppScope.read(context).backgroundSession();

  /// What the notification last showed.
  late BackgroundStatus _shown;

  /// How far the notification's countdown may be off before it's resent:
  /// the timer may run late in the background, or the wall clock be
  /// changed, and the countdown is drawn from the wall clock.
  static const _maxCountdownDrift = Duration(seconds: 1);

  /// The longest the background session is kept up after the session ends
  /// while the run is being saved (see [_stopBackground]).
  static const _maxStopDelay = Duration(seconds: 10);

  bool _backgroundStopped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Listen before starting, so "get ready" gets its cue too.
    _cues = CuePlayer(
      events: _runner.events,
      settings: AppScope.read(context).settings,
      output: _cueOutput,
    );
    _cueOutput.setKeepAwake(true);
    _runner.start();
    _runner.addListener(_onRunnerChanged);
    // Keep timing and cues going with the app in the background.
    _shown = _backgroundStatus();
    _background.start(
      _shown,
      onAction: _onNotificationAction,
      // Swiped away from recents: the service is gone, so end the session
      // rather than carry on with no notification or wake lock.
      onDismissed: () {
        if (mounted) _runner.stop();
      },
    );
  }

  /// Brings the notification in line with the screen, if anything it shows
  /// changed: the text, the button, or the countdown by more than
  /// [_maxCountdownDrift]. Cheap enough to call on every change.
  void _syncBackground() {
    if (_backgroundStopped) return;
    final status = _backgroundStatus();
    if (status.looksLike(_shown, tolerance: _maxCountdownDrift)) return;
    _shown = status;
    _background.update(status);
  }

  /// Stops the background session, once. Done as soon as the session ends,
  /// not just in [dispose]: with the app in the background the summary
  /// route's transition gets no frames, so this screen isn't disposed until
  /// the app is reopened, and the notification and wake lock would linger.
  ///
  /// With [after], the native session is only stopped once it completes
  /// (the notification stops following the screen at once, though): with no
  /// activity left, stopping lets the app's engine go (see MainActivity),
  /// which would cut short e.g. saving the run to the history.
  void _stopBackground({Future<void>? after}) {
    if (_backgroundStopped) return;
    _backgroundStopped = true;
    if (after == null) {
      _background.stop();
    } else {
      // Up until the stop: no countdown or button left from the last phase
      // (a tap on it would do nothing now).
      _shown = BackgroundStatus(
        title: widget.session.name,
        text: _runner.completed ? 'Session complete' : 'Session stopped',
      );
      _background.update(_shown);
      // Bounded: a write that never completes must not leave the service
      // and its notification up for good. Stopped even if it fails.
      after
          .timeout(_maxStopDelay, onTimeout: () {})
          .catchError((Object e) {
        debugPrint('RunningScreen: saving the run failed: $e');
      }).whenComplete(_background.stop);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _runner.removeListener(_onRunnerChanged);
    _cues.dispose();
    _runner.dispose();
    _cueOutput.setKeepAwake(false);
    _stopBackground();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Timers may have been throttled in the background; catch up at once
    // rather than on the next timer tick.
    if (state == AppLifecycleState.resumed) {
      _runner.tick();
      if (!_backgroundStopped) {
        // The activity may have been destroyed and recreated in the
        // background (the engine outlives it): keep-awake is a flag on the
        // activity's window, so set it on the new one.
        _cueOutput.setKeepAwake(true);
        // Resends the notification if its countdown is off (the timer ran
        // late, or the wall clock changed) without the runner changing, so
        // no listener fired.
        _syncBackground();
        // A start refused because the app was already in the background is
        // retried now that it's back.
        _background.ensureStarted(_shown);
      }
    }
  }

  /// "Hold · Set 2/3 · Rep 3/10 · Quad set", with a countdown to the phase's
  /// end.
  BackgroundStatus _backgroundStatus() {
    final phase = _runner.phase;
    final exercise = _runner.exercise;
    final String text;
    switch (_runner.status) {
      case RunnerStatus.waitingForTap:
        final next = _runner.nextPhase;
        // As on screen: the next exercise with phases of its own, skipping
        // any that have none.
        final nextExercise = _runner.displayExercise;
        text = switch (next) {
          null => 'Tap to continue',
          // A tap rest between sets: the next set of the same exercise.
          _ when next.exerciseIndex == phase.exerciseIndex =>
            'Tap to continue · Next: Set ${next.set}/${exercise.sets} · '
                '${exercise.name}',
          _ => 'Tap to continue · Next: ${nextExercise.name}',
        };
      default:
        text = [
          if (_runner.paused) 'Paused',
          phase.label,
          // A timed rest between sets: the set coming up, not the last
          // set's final rep.
          if (phase.kind == PhaseKind.setRest)
            'Next: Set ${phase.set + 1}/${exercise.sets}'
          else if (phase.rep > 0) ...[
            ?_runner.setLabel,
            'Rep ${phase.rep}/${exercise.reps}',
          ],
          // As on screen: the phase's own exercise, or getting ready and
          // during a timed transition, the one coming up.
          _runner.displayExercise.name,
        ].join(' · ');
    }
    return BackgroundStatus(
      title: widget.session.name,
      text: text,
      action: _actionLabel(),
      endsAt: _countdownEnd(),
    );
  }

  /// The notification button's label, mirroring the main button on screen;
  /// none while the "Stop session?" dialog is up.
  String? _actionLabel() => _confirmingStop
      ? null
      : switch (_runner.status) {
          RunnerStatus.running => 'Pause',
          RunnerStatus.paused => 'Resume',
          RunnerStatus.waitingForTap => 'Continue',
          RunnerStatus.finished => null,
        };

  /// When the current phase ends by the wall clock, not the runner's: the
  /// system draws the countdown from it. Null unless counting down.
  DateTime? _countdownEnd() => _runner.status == RunnerStatus.running
      ? (widget.now ?? DateTime.now)().add(_runner.remaining)
      : null;

  /// The notification's button does what the main button on screen does,
  /// if it still says so: a tap can race an update (the phase ended, or the
  /// session was paused on screen), and "Pause" must never resume or skip.
  /// [label] is the tapped button's label; null if unknown.
  void _onNotificationAction(String? label) {
    if (!mounted) return;
    // Also covers the "Stop session?" dialog being up (no button then): don't
    // resume or skip behind it.
    final current = _actionLabel();
    // The update with the right label is already on its way.
    if (current == null || (label != null && label != current)) return;
    if (_runner.status == RunnerStatus.waitingForTap) {
      _runner.skipPhase();
    } else {
      _runner.togglePause();
    }
  }

  void _onRunnerChanged() {
    if (_runner.status == RunnerStatus.finished) {
      _stopBackground(after: _record());
      // Anything over this screen goes first - the "Stop session?" dialog,
      // if the session ended behind it (e.g. the app was swiped away) - so
      // the summary replaces this screen, not the dialog.
      final navigator = Navigator.of(context);
      final route = ModalRoute.of(context);
      if (route != null) navigator.popUntil((r) => r == route);
      navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => SummaryScreen(
            sessionName: widget.session.name,
            completed: _runner.completed,
            reps: _runner.repsDone,
            holds: _runner.holdsDone,
            time: _runner.activeTime,
          ),
        ),
      );
    } else {
      _syncBackground();
      setState(() {});
    }
  }

  /// Adds this run to the history - unless it was stopped before a single
  /// hold or rep was done (e.g. during "get ready"), which isn't a workout.
  Future<void> _record() async {
    if (!_runner.completed && _runner.holdsDone == 0 && _runner.repsDone == 0) {
      return;
    }
    // Looked up now: this screen is replaced by the summary straight away.
    final history = AppScope.read(context).history;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await history.add(HistoryEntry.record(
        session: widget.session,
        endedAt: (widget.now ?? DateTime.now)(),
        completed: _runner.completed,
        reps: _runner.repsDone,
        holds: _runner.holdsDone,
        activeTime: _runner.activeTime,
      ));
    } on Object catch (e) {
      // E.g. web storage full: the run would be gone on the next launch.
      debugPrint('RunningScreen: could not save the run to history: $e');
      messenger.showSnackBar(const SnackBar(
        content: Text("Couldn't save this run to your history"),
      ));
    }
  }

  /// Guards against a second "Stop session?" dialog (double tap on the
  /// close button, or close plus back).
  bool _confirmingStop = false;

  Future<void> _confirmStop() async {
    if (_confirmingStop || _runner.status == RunnerStatus.finished) return;
    _confirmingStop = true;
    final wasRunning = _runner.status == RunnerStatus.running;
    _runner.pause();
    // pause() catches up first, which may have just ended the session.
    if (_runner.status == RunnerStatus.finished) {
      _confirmingStop = false;
      return;
    }
    // Takes the button off the notification, also when pause() changed
    // nothing (already paused, or waiting for a tap). A no-op if pause()
    // already did it.
    _syncBackground();
    final bool stop;
    try {
      stop = await showConfirmDialog(
        context,
        title: 'Stop session?',
        message: 'You can see what you did so far on the next screen.',
        confirmLabel: 'Stop',
      );
    } finally {
      _confirmingStop = false;
    }
    // Ended meanwhile (the dialog was closed for the summary): nothing to
    // stop or resume.
    if (!mounted || _runner.status == RunnerStatus.finished) return;
    if (stop) {
      _runner.stop();
      return;
    }
    // Resuming updates the notification; otherwise nothing changes on the
    // runner, but the button has to come back.
    if (wasRunning) _runner.resume();
    _syncBackground();
  }

  @override
  Widget build(BuildContext context) {
    final runner = _runner;
    // Once finished, keep drawing this last frame (input off) while the
    // summary slides in over it, rather than a blank page.
    final finished = runner.status == RunnerStatus.finished;
    final phase = runner.phase;
    final exercise = runner.exercise;
    final isTempo = exercise is TempoExercise;
    final inExercise = phase.rep > 0;
    final exerciseCount = widget.session.exercises.length;
    // During a transition, the exercise coming up (as on get ready).
    final shownIndex = runner.displayExerciseIndex;
    final setLabel = runner.setLabel;
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final showTempoLook = isTempo && inExercise;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmStop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Stop',
            onPressed: finished ? null : _confirmStop,
            icon: const Icon(Icons.close),
          ),
          title: Text(widget.session.name),
          actions: [
            _CueToggles(
              settings: AppScope.of(context).settings,
              vibrationAvailable: _cueOutput.vibrationAvailable,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: _LiveProgressBar(runner: runner),
          ),
        ),
        body: IgnorePointer(
          ignoring: finished,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  // Exercise x/y, name, set x/y.
                  Text(
                    'Exercise ${shownIndex + 1}/$exerciseCount',
                    style: textTheme.labelLarge
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  Text(
                    runner.displayExercise.name,
                    style: textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(
                    height: 24,
                    child: setLabel != null
                        ? Text(setLabel, style: textTheme.titleMedium)
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        // Tempo exercises get a violet tinted panel.
                        color: showTempoLook
                            ? PhaseColors.move.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(28),
                        border: showTempoLook
                            ? Border.all(
                                color: PhaseColors.move.withValues(alpha: 0.35))
                            : null,
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: runner.status == RunnerStatus.waitingForTap
                                  ? runner.skipPhase
                                  : null,
                              child: Center(child: _LiveTimer(runner: runner)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 48,
                            child: inExercise
                                ? RepDots(
                                    reps: exercise.reps,
                                    repsDone: phase.repsDone,
                                    color: isTempo
                                        ? PhaseColors.move
                                        : PhaseColors.hold1,
                                    square: isTempo,
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _NextUp(runner: runner),
                  const SizedBox(height: 12),
                  _Controls(runner: runner),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The ring (or, for Tempo reps, the tempo curve) and the countdown,
/// repainted every frame while running so it moves smoothly.
class _LiveTimer extends StatefulWidget {
  const _LiveTimer({required this.runner});

  final SessionRunner runner;

  @override
  State<_LiveTimer> createState() => _LiveTimerState();
}

class _LiveTimerState extends State<_LiveTimer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    // Repaint every frame only while the clock runs: a started ticker
    // schedules a frame every vsync, paused or not.
    // Tick on every frame too, so a phase change lands on the exact frame
    // its time runs out instead of up to 100 ms later (showing 0 and an
    // empty ring meanwhile).
    _ticker = createTicker((_) {
      widget.runner.tick();
      if (mounted) setState(() {});
    });
    widget.runner.addListener(_syncTicker);
    _syncTicker();
  }

  @override
  void didUpdateWidget(_LiveTimer old) {
    super.didUpdateWidget(old);
    if (old.runner != widget.runner) {
      old.runner.removeListener(_syncTicker);
      widget.runner.addListener(_syncTicker);
      _syncTicker();
    }
  }

  void _syncTicker() {
    final running = widget.runner.status == RunnerStatus.running;
    if (running && !_ticker.isActive) _ticker.start();
    if (!running && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    widget.runner.removeListener(_syncTicker);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runner = widget.runner;
    final phase = runner.phase;
    final color = PhaseColors.of(phase.kind);
    final textTheme = Theme.of(context).textTheme;
    final waiting = runner.status == RunnerStatus.waitingForTap;
    final exercise = runner.exercise;

    final String? footer = switch (phase.kind) {
      PhaseKind.getReady ||
      PhaseKind.transition ||
      PhaseKind.waitForTap =>
        null,
      _ when phase.waitsForTap => 'Tap when ready',
      _ => 'Rep ${phase.rep}/${exercise.reps}',
    };

    final center = FittedBox(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            phase.label.toUpperCase(),
            style: textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          if (waiting)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Icon(Icons.touch_app, size: 96, color: color),
            )
          else
            Text(
              '${runner.secondsLeft}',
              style: textTheme.displayLarge?.copyWith(
                fontSize: 112,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                height: 1.1,
                color: runner.paused
                    ? textTheme.displayLarge?.color?.withValues(alpha: 0.4)
                    : null,
              ),
            ),
          if (footer != null) Text(footer, style: textTheme.titleLarge),
          if (runner.paused)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'PAUSED',
                style: textTheme.labelLarge?.copyWith(letterSpacing: 2),
              ),
            ),
        ],
      ),
    );

    // Tempo reps: the movement curve with the countdown below it.
    if (exercise is TempoExercise && phase.rep > 0) {
      final segment = switch (phase.kind) {
        PhaseKind.move => 0,
        PhaseKind.tempoHold => 1,
        PhaseKind.back => 2,
        _ => null, // rest between sets: back at the start
      };
      return Column(
        children: [
          Expanded(
            flex: 5,
            child: TempoCurve(
              moveSeconds: exercise.moveSeconds,
              holdSeconds: exercise.holdSeconds,
              returnSeconds: exercise.returnSeconds,
              progress: segment == null
                  ? 0
                  : TempoCurve.progressAt(
                      segment: segment,
                      fractionDone: 1 - runner.fractionLeft,
                      moveSeconds: exercise.moveSeconds,
                      holdSeconds: exercise.holdSeconds,
                      returnSeconds: exercise.returnSeconds,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(flex: 4, child: center),
        ],
      );
    }
    return PhaseRing(
      fractionLeft: waiting ? 1 : runner.fractionLeft,
      color: color,
      child: center,
    );
  }
}

/// The whole-session progress bar under the app bar, repainted every frame
/// while running so it creeps along smoothly.
class _LiveProgressBar extends StatefulWidget {
  const _LiveProgressBar({required this.runner});

  final SessionRunner runner;

  @override
  State<_LiveProgressBar> createState() => _LiveProgressBarState();
}

class _LiveProgressBarState extends State<_LiveProgressBar>
    with SingleTickerProviderStateMixin {
  // _LiveTimer already ticks the runner each frame; this only repaints.
  late final Ticker _ticker = createTicker((_) {
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    widget.runner.addListener(_syncTicker);
    _syncTicker();
  }

  @override
  void didUpdateWidget(_LiveProgressBar old) {
    super.didUpdateWidget(old);
    if (old.runner != widget.runner) {
      old.runner.removeListener(_syncTicker);
      widget.runner.addListener(_syncTicker);
      _syncTicker();
    }
  }

  void _syncTicker() {
    final running = widget.runner.status == RunnerStatus.running;
    if (running && !_ticker.isActive) _ticker.start();
    if (!running && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    widget.runner.removeListener(_syncTicker);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runner = widget.runner;
    final color = PhaseColors.of(runner.phase.kind);
    return SessionProgressBar(
      progress: runner.sessionProgress,
      color: runner.paused ? color.withValues(alpha: 0.4) : color,
    );
  }
}

extension on SessionRunner {
  bool get paused => status == RunnerStatus.paused;
}

/// "Next: Rest · 3 s", or the next exercise's name at an exercise boundary.
class _NextUp extends StatelessWidget {
  const _NextUp({required this.runner});

  final SessionRunner runner;

  @override
  Widget build(BuildContext context) {
    final next = runner.nextPhase;
    final current = runner.phase.kind;
    final textTheme = Theme.of(context).textTheme;
    final exercises = runner.session.exercises;
    final String text;
    Color? dot;
    if (next == null) {
      text = 'Next: done!';
    } else if (SessionRunner.isBetweenExercises(current)) {
      // Get ready / transition: what exercise is coming.
      text = 'Next: ${runner.displayExercise.name}';
      dot = PhaseColors.of(next.kind);
    } else if (SessionRunner.isBetweenExercises(next.kind) ||
        next.exerciseIndex != runner.phase.exerciseIndex) {
      // Last phase of this exercise: name the next exercise, past any
      // transition.
      final upcoming = runner.upcomingExerciseIndex ?? next.exerciseIndex;
      text = 'Next: ${exercises[upcoming].name}';
      dot = PhaseColors.of(next.kind);
    } else if (next.waitsForTap) {
      text = 'Next: ${next.label} (tap)';
      dot = PhaseColors.of(next.kind);
    } else {
      text = 'Next: ${next.label} · ${next.seconds} s';
      dot = PhaseColors.of(next.kind);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          if (dot != null) ...[
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              text,
              style: textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.runner});

  final SessionRunner runner;

  @override
  Widget build(BuildContext context) {
    final waiting = runner.status == RunnerStatus.waitingForTap;
    final running = runner.status == RunnerStatus.running;
    // Spread over the full width, but scaled down rather than overflowing
    // on narrow screens.
    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.scaleDown,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: _row(context, waiting: waiting, running: running),
        ),
      ),
    );
  }

  Widget _row(BuildContext context,
      {required bool waiting, required bool running}) {
    const big = Size(88, 88);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _SideButton(
          icon: Icons.fast_rewind,
          label: runner.previousRestarts ? 'Restart' : 'Previous',
          tooltip: runner.previousRestarts
              ? 'Restart exercise'
              : 'Previous exercise',
          onPressed: runner.canGoBack ? runner.previousExercise : null,
        ),
        _SideButton(
          icon: Icons.skip_next,
          label: 'Skip phase',
          onPressed: waiting ? null : runner.skipPhase,
        ),
        waiting
            ? FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(140, 88),
                  shape: const StadiumBorder(),
                  textStyle: Theme.of(context).textTheme.titleLarge,
                ),
                onPressed: runner.skipPhase,
                child: const Text('Continue'),
              )
            : FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: big,
                  maximumSize: big,
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                ),
                onPressed: runner.togglePause,
                child: Icon(
                  running ? Icons.pause : Icons.play_arrow,
                  size: 48,
                  semanticLabel: running ? 'Pause' : 'Resume',
                ),
              ),
        _SideButton(
          icon: Icons.fast_forward,
          label: 'Skip exercise',
          onPressed: runner.skipExercise,
        ),
      ],
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final String label;

  /// Defaults to [label].
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          tooltip: tooltip ?? label,
          iconSize: 32,
          style: IconButton.styleFrom(minimumSize: const Size(64, 64)),
          onPressed: onPressed,
          icon: Icon(icon),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

/// Quick sound/vibration switches, same settings as the Settings screen.
class _CueToggles extends StatelessWidget {
  const _CueToggles({
    required this.settings,
    required this.vibrationAvailable,
  });

  final SettingsStore settings;
  final ValueListenable<bool> vibrationAvailable;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([settings, vibrationAvailable]),
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: settings.soundOn ? 'Mute sounds' : 'Unmute sounds',
            isSelected: settings.soundOn,
            onPressed: () => settings.setSoundOn(!settings.soundOn),
            icon: const Icon(Icons.volume_off),
            selectedIcon: const Icon(Icons.volume_up),
          ),
          if (vibrationAvailable.value)
            IconButton(
              tooltip: settings.vibrationOn
                  ? 'Turn off vibration'
                  : 'Turn on vibration',
              isSelected: settings.vibrationOn,
              onPressed: () => settings.setVibrationOn(!settings.vibrationOn),
              icon: const Icon(Icons.mobile_off),
              selectedIcon: const Icon(Icons.vibration),
            ),
        ],
      ),
    );
  }
}
