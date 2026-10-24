import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../engine/session_plan.dart';
import '../models/history_entry.dart';
import '../widgets/dialogs.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];

/// e.g. "Mon 12 October", plus the year when it isn't this year's.
String formatDay(DateTime day, DateTime now) =>
    '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}'
    '${day.year == now.year ? '' : ' ${day.year}'}';

String _formatTime(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}';

/// Past runs: streaks, a month calendar of the days exercised, and every
/// run by day. Only [sessionId]'s runs when set.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.sessionId, this.sessionName, this.now});

  final String? sessionId;

  /// Shown in the title when [sessionId] is set.
  final String? sessionName;

  /// Injectable for tests.
  final DateTime Function()? now;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _now() => (widget.now ?? DateTime.now)();

  /// First day of the month the calendar shows.
  late DateTime _month = DateTime(_now().year, _now().month);

  /// When set, the list only shows this day's runs.
  DateTime? _selectedDay;

  Future<void> _clear() async {
    final history = AppScope.of(context).history;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Clear history?',
      message: widget.sessionId == null
          ? 'Every recorded run will be deleted.'
          : 'Every recorded run of "${widget.sessionName}" will be deleted.',
      confirmLabel: 'Clear',
    );
    if (confirmed && mounted) {
      await history.clear(sessionId: widget.sessionId);
      setState(() => _selectedDay = null);
    }
  }

  void _delete(HistoryEntry entry) {
    final history = AppScope.of(context).history;
    history.delete(entry.id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Run deleted'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => history.add(entry),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final history = AppScope.of(context).history;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.sessionId == null
              ? 'History'
              : 'History · ${widget.sessionName}',
        ),
        actions: [
          ListenableBuilder(
            listenable: history,
            builder: (context, _) => IconButton(
              tooltip: 'Clear history',
              onPressed:
                  history.entriesFor(widget.sessionId).isEmpty ? null : _clear,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: history,
        builder: (context, _) {
          final entries = history.entriesFor(widget.sessionId);
          if (entries.isEmpty) return const _EmptyState();
          final now = _now();
          final streaks = Streaks.of(entries, now);
          final selected = _selectedDay;
          // A deleted run can leave the selected day empty: show everything.
          final shown = selected == null
              ? entries
              : entries.where((e) => dayOf(e.endedAt) == selected).toList();
          final byDay = <DateTime, List<HistoryEntry>>{};
          for (final e in shown.isEmpty ? entries : shown) {
            (byDay[dayOf(e.endedAt)] ??= []).add(e);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
            children: [
              Row(
                children: [
                  _Stat(label: 'Current streak', value: _days(streaks.current)),
                  const SizedBox(width: 8),
                  _Stat(label: 'Best streak', value: _days(streaks.best)),
                  const SizedBox(width: 8),
                  _Stat(label: 'Runs', value: '${entries.length}'),
                ],
              ),
              const SizedBox(height: 12),
              _MonthCalendar(
                month: _month,
                today: dayOf(now),
                selectedDay: shown.isEmpty ? null : selected,
                entries: entries,
                onMonthChanged: (m) => setState(() => _month = m),
                onDayTapped: (day) => setState(
                  () => _selectedDay = day == _selectedDay ? null : day,
                ),
              ),
              if (selected != null && shown.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      label: Text(formatDay(selected, now)),
                      onDeleted: () => setState(() => _selectedDay = null),
                      deleteButtonTooltipMessage: 'Show all days',
                    ),
                  ),
                ),
              for (final MapEntry(key: day, value: dayEntries)
                  in byDay.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Text(
                    formatDay(day, now),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                for (final entry in dayEntries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _EntryCard(
                      entry: entry,
                      showSessionName: widget.sessionId == null,
                      onDelete: () => _delete(entry),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

String _days(int n) => n == 1 ? '1 day' : '$n days';

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history,
              size: 96,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('No runs yet', style: textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Every session you run will be recorded here.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
          ],
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
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            FittedBox(child: Text(value, style: textTheme.titleLarge)),
            const SizedBox(height: 4),
            FittedBox(child: Text(label, style: textTheme.labelMedium)),
          ],
        ),
      ),
    );
  }
}

/// One month, Monday first. Days with a completed run are filled, days
/// with only stopped runs are tinted.
class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.today,
    required this.selectedDay,
    required this.entries,
    required this.onMonthChanged,
    required this.onDayTapped,
  });

  final DateTime month;
  final DateTime today;
  final DateTime? selectedDay;
  final List<HistoryEntry> entries;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDayTapped;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // Day -> whether any run that day was completed.
    final done = <DateTime, bool>{};
    for (final e in entries) {
      final day = dayOf(e.endedAt);
      done[day] = (done[day] ?? false) || e.completed;
    }
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = month.weekday - 1;
    final isCurrentMonth =
        month.year == today.year && month.month == today.month;

    Widget dayCell(int d) {
      final day = DateTime(month.year, month.month, d);
      final completed = done[day];
      final selected = day == selectedDay;
      final Color? fill = switch (completed) {
        true => colors.primary,
        false => colors.primaryContainer,
        null => null,
      };
      return Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: fill ?? Colors.transparent,
          shape: CircleBorder(
            side: selected
                ? BorderSide(color: colors.tertiary, width: 3)
                : day == today
                    ? BorderSide(color: colors.outline)
                    : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: completed == null ? null : () => onDayTapped(day),
            child: Center(
              child: Text(
                '$d',
                style: textTheme.bodyMedium?.copyWith(
                  color: completed == true
                      ? colors.onPrimary
                      : completed == false
                          ? colors.onPrimaryContainer
                          : null,
                  fontWeight: completed == null ? null : FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () =>
                      onMonthChanged(DateTime(month.year, month.month - 1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${_months[month.month - 1]} ${month.year}',
                    textAlign: TextAlign.center,
                    style: textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: isCurrentMonth
                      ? null
                      : () => onMonthChanged(
                            DateTime(month.year, month.month + 1),
                          ),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            // Square day cells, capped so they don't grow huge on wide
            // (desktop web) screens.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  Row(
                    children: [
                      for (final w in _weekdays)
                        Expanded(
                          child: Text(
                            w.substring(0, 1),
                            textAlign: TextAlign.center,
                            style: textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  GridView.count(
                    crossAxisCount: 7,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (var i = 0; i < leading; i++) const SizedBox.shrink(),
                      for (var d = 1; d <= daysInMonth; d++) dayCell(d),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.entry,
    required this.showSessionName,
    required this.onDelete,
  });

  final HistoryEntry entry;
  final bool showSessionName;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final time = _formatTime(entry.endedAt);
    final stats = [
      if (entry.reps > 0) entry.reps == 1 ? '1 rep' : '${entry.reps} reps',
      if (entry.holds > 0) entry.holds == 1 ? '1 hold' : '${entry.holds} holds',
      formatDuration(entry.activeTime),
    ].join(' · ');
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, color: colors.onErrorContainer),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(
            entry.completed ? Icons.check_circle : Icons.stop_circle_outlined,
            color: entry.completed ? colors.primary : colors.onSurfaceVariant,
          ),
          title: Text(showSessionName ? entry.sessionName : time),
          subtitle: Text(
            [
              if (showSessionName) time,
              if (!entry.completed) 'Stopped',
              stats,
            ].join(' · '),
          ),
          trailing: IconButton(
            tooltip: 'Delete run',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ),
      ),
    );
  }
}
