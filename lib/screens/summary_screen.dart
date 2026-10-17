import 'package:flutter/material.dart';

import '../engine/session_plan.dart';

/// Shown when a session ends (or is stopped): reps, holds and time.
class SummaryScreen extends StatelessWidget {
  const SummaryScreen({
    super.key,
    required this.sessionName,
    required this.completed,
    required this.reps,
    required this.holds,
    required this.time,
  });

  final String sessionName;

  /// False when stopped early.
  final bool completed;
  final int reps;
  final int holds;
  final Duration time;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Icon(
                completed ? Icons.check_circle : Icons.stop_circle_outlined,
                size: 96,
                color: completed ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                completed ? 'Session complete' : 'Session stopped',
                style: textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(sessionName,
                  style: textTheme.titleMedium
                      ?.copyWith(color: colors.onSurfaceVariant)),
              const SizedBox(height: 32),
              Row(
                children: [
                  _Stat(label: 'Reps', value: '$reps'),
                  const SizedBox(width: 12),
                  _Stat(label: 'Holds', value: '$holds'),
                  const SizedBox(width: 12),
                  _Stat(label: 'Time', value: formatDuration(time)),
                ],
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            FittedBox(child: Text(value, style: textTheme.headlineMedium)),
            const SizedBox(height: 4),
            Text(label, style: textTheme.labelLarge),
          ],
        ),
      ),
    );
  }
}
