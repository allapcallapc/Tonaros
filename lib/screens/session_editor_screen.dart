import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/session.dart';
import '../services/session_store.dart';
import '../theme/phase_colors.dart';
import '../widgets/dialogs.dart';
import '../widgets/exercise_summary.dart';
import '../widgets/number_stepper.dart';
import 'exercise_editor_screen.dart';
import 'running_screen.dart';

/// Opens the running screen for [session].
void startSession(BuildContext context, Session session) {
  if (session.exercises.isEmpty) return;
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => RunningScreen(session: session)),
  );
}

/// A session's exercises and the transitions between them. Every change is
/// saved straight away.
class SessionEditorScreen extends StatelessWidget {
  const SessionEditorScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).sessions;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final session = store.byId(sessionId);
        // Deleted from elsewhere; this screen is about to be popped.
        if (session == null) return const Scaffold();
        return _SessionEditor(session: session);
      },
    );
  }
}

class _SessionEditor extends StatelessWidget {
  const _SessionEditor({required this.session});

  final Session session;

  SessionStore _store(BuildContext context) => AppScope.of(context).sessions;

  /// Applies [change] to the session as it is in [store] now, not to the
  /// [session] this widget was built with: a dialog or route may have been
  /// open in between, and other changes (an Undo) may have landed meanwhile.
  static void _change(
    SessionStore store,
    String sessionId,
    Session Function(Session current) change,
  ) {
    final current = store.byId(sessionId);
    if (current != null) store.update(change(current));
  }

  void _changeExercises(
    BuildContext context,
    List<Exercise> Function(List<Exercise> current) change,
  ) =>
      _change(_store(context), session.id,
          (s) => s.copyWith(exercises: change([...s.exercises])));

  Future<void> _rename(BuildContext context) async {
    final name = await showTextInputDialog(
      context,
      title: 'Rename session',
      initialValue: session.name,
      confirmLabel: 'Rename',
    );
    if (name != null && context.mounted) {
      _change(_store(context), session.id, (s) => s.copyWith(name: name));
    }
  }

  Future<void> _add(BuildContext context) async {
    final tempo = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const _TypeBadge(tempo: false),
              title: const Text('Hold'),
              subtitle: const Text('reps × hold, rest between reps'),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              leading: const _TypeBadge(tempo: true),
              title: const Text('Tempo'),
              subtitle: const Text('reps × (move → hold → return)'),
              onTap: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (tempo == null || !context.mounted) return;
    final created = await Navigator.push<Exercise>(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseEditorScreen(
          exercise: tempo ? TempoExercise.blank() : HoldExercise.blank(),
          isNew: true,
        ),
      ),
    );
    if (created != null && context.mounted) {
      _changeExercises(context, (list) => list..add(created));
    }
  }

  Future<void> _edit(BuildContext context, int index) async {
    final edited = await Navigator.push<Exercise>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ExerciseEditorScreen(exercise: session.exercises[index]),
      ),
    );
    // Matched by id: the exercise may have moved since the editor opened.
    if (edited != null && context.mounted) {
      _changeExercises(context, (list) => [
            for (final e in list) e.id == edited.id ? edited : e,
          ]);
    }
  }

  void _duplicate(BuildContext context, int index) {
    final e = session.exercises[index];
    _changeExercises(context,
        (list) => list..insert(index + 1, e.copyWithCommon(id: newId())));
  }

  void _remove(BuildContext context, int index) {
    final removed = session.exercises[index];
    final store = _store(context);
    _changeExercises(context, (list) => list..removeAt(index));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Removed "${removed.name}"'),
        action: SnackBarAction(
          label: 'Undo',
          // Puts back just this exercise, keeping anything changed since.
          onPressed: () => _change(store, session.id, (s) {
            if (s.exercises.any((e) => e.id == removed.id)) return s;
            final list = [...s.exercises];
            return s.copyWith(
                exercises: list..insert(index.clamp(0, list.length), removed));
          }),
        ),
      ));
  }

  void _reorder(BuildContext context, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    _changeExercises(
        context, (list) => list..insert(newIndex, list.removeAt(oldIndex)));
  }

  Future<void> _editTransition(BuildContext context, int index) async {
    final e = session.exercises[index];
    final result = await showModalBottomSheet<Transition>(
      context: context,
      showDragHandle: true,
      builder: (_) => _TransitionSheet(initial: e.transition),
    );
    if (result != null && context.mounted) {
      _changeExercises(context, (list) => [
            for (final x in list)
              x.id == e.id ? x.copyWithCommon(transition: result) : x,
          ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exercises = session.exercises;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(session.name),
        actions: [
          IconButton(
            tooltip: 'Rename',
            onPressed: () => _rename(context),
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      bottomNavigationBar: exercises.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(60),
                    textStyle: textTheme.titleLarge,
                  ),
                  onPressed: () => startSession(context, session),
                  icon: const Icon(Icons.play_arrow, size: 32),
                  label: const Text('Start'),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Add exercise'),
      ),
      body: exercises.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No exercises yet.\nAdd one to build this session.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge,
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined),
                      const SizedBox(width: 8),
                      Text(sessionDurationLabel(session),
                          style: textTheme.titleMedium),
                      const Spacer(),
                      Text(
                        exercises.length == 1
                            ? '1 exercise'
                            : '${exercises.length} exercises',
                        style: textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                    itemCount: exercises.length,
                    onReorder: (a, b) => _reorder(context, a, b),
                    itemBuilder: (context, i) => Column(
                      key: ValueKey(exercises[i].id),
                      children: [
                        _ExerciseCard(
                          index: i,
                          exercise: exercises[i],
                          onTap: () => _edit(context, i),
                          onDuplicate: () => _duplicate(context, i),
                          onRemove: () => _remove(context, i),
                        ),
                        if (i < exercises.length - 1)
                          _TransitionRow(
                            transition: exercises[i].transition,
                            onTap: () => _editTransition(context, i),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Pink round badge for Hold, violet square badge for Tempo - the same
/// shapes as the running screen's rep dots.
class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.tempo});

  final bool tempo;

  @override
  Widget build(BuildContext context) {
    final color = tempo ? PhaseColors.move : PhaseColors.hold1;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: tempo ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: tempo ? BorderRadius.circular(8) : null,
      ),
      child: Icon(
        tempo ? Icons.swap_vert : Icons.pan_tool_alt_outlined,
        color: color,
      ),
    );
  }
}

enum _ExerciseAction { duplicate, remove }

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.index,
    required this.exercise,
    required this.onTap,
    required this.onDuplicate,
    required this.onRemove,
  });

  final int index;
  final Exercise exercise;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 12, right: 4),
        minVerticalPadding: 12,
        leading: _TypeBadge(tempo: exercise is TempoExercise),
        title: Text(exercise.name),
        subtitle: Text(exerciseSummary(exercise)),
        onTap: onTap,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<_ExerciseAction>(
              tooltip: 'More',
              onSelected: (a) => switch (a) {
                _ExerciseAction.duplicate => onDuplicate(),
                _ExerciseAction.remove => onRemove(),
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _ExerciseAction.duplicate,
                  child: Text('Duplicate'),
                ),
                PopupMenuItem(
                  value: _ExerciseAction.remove,
                  child: Text('Remove'),
                ),
              ],
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.drag_handle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransitionRow extends StatelessWidget {
  const _TransitionRow({required this.transition, required this.onTap});

  final Transition transition;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              transition.kind == TransitionKind.tap
                  ? Icons.touch_app_outlined
                  : Icons.arrow_downward,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Text(transitionLabel(transition),
                style: TextStyle(color: color)),
            const SizedBox(width: 4),
            Icon(Icons.edit, size: 14, color: color),
          ],
        ),
      ),
    );
  }
}

class _TransitionSheet extends StatefulWidget {
  const _TransitionSheet({required this.initial});

  final Transition initial;

  @override
  State<_TransitionSheet> createState() => _TransitionSheetState();
}

class _TransitionSheetState extends State<_TransitionSheet> {
  late TransitionKind _kind = widget.initial.kind;
  late int _seconds =
      widget.initial.kind == TransitionKind.tap ? 10 : widget.initial.seconds;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Transition to next exercise',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            SegmentedButton<TransitionKind>(
              segments: const [
                ButtonSegment(
                  value: TransitionKind.countdown,
                  label: Text('Countdown'),
                  icon: Icon(Icons.timer_outlined),
                ),
                ButtonSegment(
                  value: TransitionKind.tap,
                  label: Text('Wait for tap'),
                  icon: Icon(Icons.touch_app_outlined),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 8),
            if (_kind == TransitionKind.countdown)
              NumberStepper(
                label: 'Countdown',
                unit: 's',
                value: _seconds,
                onChanged: (v) => setState(() => _seconds = v),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                _kind == TransitionKind.tap
                    ? const Transition.tap()
                    : Transition.countdown(_seconds),
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
