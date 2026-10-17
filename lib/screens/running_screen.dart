import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../engine/session_plan.dart';
import '../engine/session_runner.dart';
import '../models/session.dart';
import '../theme/phase_colors.dart';
import '../widgets/dialogs.dart';
import '../widgets/phase_ring.dart';
import '../widgets/rep_dots.dart';
import '../widgets/tempo_curve.dart';
import 'summary_screen.dart';

/// Runs a session: 3 s get ready, then every exercise and transition.
class RunningScreen extends StatefulWidget {
  const RunningScreen({super.key, required this.session, this.clock});

  final Session session;

  /// Injectable for tests.
  final DateTime Function()? clock;

  @override
  State<RunningScreen> createState() => _RunningScreenState();
}

class _RunningScreenState extends State<RunningScreen>
    with WidgetsBindingObserver {
  late final SessionRunner _runner =
      SessionRunner(widget.session, clock: widget.clock);
  bool _stoppedEarly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _runner.addListener(_onRunnerChanged);
    _runner.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _runner.removeListener(_onRunnerChanged);
    _runner.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Timers may have been throttled in the background; catch up at once
    // rather than on the next timer tick.
    if (state == AppLifecycleState.resumed) _runner.tick();
  }

  void _onRunnerChanged() {
    if (_runner.status == RunnerStatus.finished) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SummaryScreen(
            sessionName: widget.session.name,
            completed: !_stoppedEarly,
            reps: _runner.repsDone,
            holds: _runner.holdsDone,
            time: _runner.activeTime,
          ),
        ),
      );
    } else {
      setState(() {});
    }
  }

  Future<void> _confirmStop() async {
    final wasRunning = _runner.status == RunnerStatus.running;
    _runner.pause();
    final stop = await showConfirmDialog(
      context,
      title: 'Stop session?',
      message: 'You can see what you did so far on the next screen.',
      confirmLabel: 'Stop',
    );
    if (!mounted) return;
    if (stop) {
      _stoppedEarly = true;
      _runner.stop();
    } else if (wasRunning) {
      _runner.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final runner = _runner;
    if (runner.status == RunnerStatus.finished) return const Scaffold();
    final phase = runner.phase;
    final exercise = runner.exercise;
    final isTempo = exercise is TempoExercise;
    final inExercise = phase.rep > 0;
    final exerciseCount = widget.session.exercises.length;
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
            onPressed: _confirmStop,
            icon: const Icon(Icons.close),
          ),
          title: Text(widget.session.name),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                // Exercise x/y, name, set x/y.
                Text(
                  'Exercise ${phase.exerciseIndex + 1}/$exerciseCount',
                  style: textTheme.labelLarge
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                Text(
                  exercise.name,
                  style: textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(
                  height: 24,
                  child: inExercise && exercise.sets > 1
                      ? Text('Set ${phase.set}/${exercise.sets}',
                          style: textTheme.titleMedium)
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
    _ticker = createTicker((_) {
      if (widget.runner.status == RunnerStatus.running) setState(() {});
    })
      ..start();
  }

  @override
  void dispose() {
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
    bool between(PhaseKind k) =>
        k == PhaseKind.getReady ||
        k == PhaseKind.transition ||
        k == PhaseKind.waitForTap;
    final String text;
    Color? dot;
    if (next == null) {
      text = 'Next: done!';
    } else if (between(current)) {
      // Get ready / transition: what exercise is coming.
      text = 'Next: ${exercises[next.exerciseIndex].name}';
      dot = PhaseColors.of(next.kind);
    } else if (between(next.kind) ||
        next.exerciseIndex != runner.phase.exerciseIndex) {
      // Last phase of this exercise.
      text = 'Next: ${exercises[runner.phase.exerciseIndex + 1].name}';
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
    const big = Size(88, 88);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
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
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          tooltip: label,
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
