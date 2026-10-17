import 'dart:convert';

import 'package:flutter/material.dart';

import '../engine/session_plan.dart';
import '../models/session.dart';
import '../widgets/dialogs.dart';
import '../widgets/number_stepper.dart';

/// Edits a copy of an exercise; pops with the result on Save, or null.
class ExerciseEditorScreen extends StatefulWidget {
  const ExerciseEditorScreen({super.key, required this.exercise, this.isNew = false});

  final Exercise exercise;
  final bool isNew;

  @override
  State<ExerciseEditorScreen> createState() => _ExerciseEditorScreenState();
}

class _ExerciseEditorScreenState extends State<ExerciseEditorScreen> {
  late Exercise _exercise = widget.exercise;

  /// Kept so switching type back and forth doesn't lose what was entered.
  late HoldExercise _hold = switch (widget.exercise) {
    HoldExercise e => e,
    _ => HoldExercise.blank().copyWith(id: widget.exercise.id),
  };
  late TempoExercise _tempo = switch (widget.exercise) {
    TempoExercise e => e,
    _ => TempoExercise.blank().copyWith(id: widget.exercise.id),
  };

  late final _name = TextEditingController(text: widget.exercise.name);
  late final _firstHoldName = TextEditingController(text: _hold.firstHoldName);
  late final _secondHoldName =
      TextEditingController(text: _hold.secondHoldName);

  @override
  void dispose() {
    _name.dispose();
    _firstHoldName.dispose();
    _secondHoldName.dispose();
    super.dispose();
  }

  void _set(Exercise e) => setState(() {
        _exercise = e;
        switch (e) {
          case HoldExercise h:
            _hold = h;
          case TempoExercise t:
            _tempo = t;
        }
      });

  void _switchType(bool tempo) {
    // Carry the shared fields over to the other type.
    final from = _exercise;
    final to = tempo ? _tempo : _hold;
    _set(to.copyWithCommon(
      sets: from.sets,
      restBetweenSets: from.restBetweenSets,
      tapBetweenSets: from.tapBetweenSets,
      transition: from.transition,
    ));
  }

  /// The exercise as currently entered; blank names get a default only
  /// [withDefaults].
  Exercise _entered({required bool withDefaults}) {
    String text(TextEditingController c, String fallback) {
      final t = c.text.trim();
      return t.isEmpty && withDefaults ? fallback : t;
    }

    var result = _exercise.copyWithCommon(
      name: text(
          _name, _exercise is TempoExercise ? 'Tempo exercise' : 'Hold exercise'),
    );
    if (result is HoldExercise) {
      result = result.copyWith(
        firstHoldName: text(_firstHoldName, 'Left'),
        secondHoldName: text(_secondHoldName, 'Right'),
      );
    }
    return result;
  }

  void _save() => Navigator.pop(context, _entered(withDefaults: true));

  bool get _hasChanges =>
      jsonEncode(_entered(withDefaults: false).toJson()) !=
      jsonEncode(widget.exercise.toJson());

  /// Back (app bar or system) asks before throwing away unsaved changes.
  Future<void> _onPop(bool didPop, Object? _) async {
    if (didPop) return;
    final discard = !_hasChanges ||
        await showConfirmDialog(
          context,
          title: 'Discard changes?',
          message: widget.isNew
              ? 'This exercise will not be added.'
              : 'Your changes to this exercise will be lost.',
          confirmLabel: 'Discard',
        );
    if (discard && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final e = _exercise;
    final textTheme = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPop,
      child: Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New exercise' : 'Edit exercise'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
              onPressed: _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextField(
              controller: _name,
              autofocus: widget.isNew,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Calf raise',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Hold'),
                  icon: Icon(Icons.pan_tool_alt_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Tempo'),
                  icon: Icon(Icons.swap_vert),
                ),
              ],
              selected: {e is TempoExercise},
              onSelectionChanged: (s) => _switchType(s.first),
            ),
            const SizedBox(height: 16),
            ...switch (e) {
              HoldExercise h => _holdFields(h),
              TempoExercise t => _tempoFields(t),
            },
            const Divider(height: 32),
            NumberStepper(
              label: 'Sets',
              value: e.sets,
              min: 1,
              onChanged: (v) => _set(e.copyWithCommon(sets: v)),
            ),
            if (e.sets > 1) ...[
              const SizedBox(height: 8),
              Text('Rest between sets', style: textTheme.bodyLarge),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Countdown'),
                    icon: Icon(Icons.timer_outlined),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Wait for tap'),
                    icon: Icon(Icons.touch_app_outlined),
                  ),
                ],
                selected: {e.tapBetweenSets},
                onSelectionChanged: (s) =>
                    _set(e.copyWithCommon(tapBetweenSets: s.first)),
              ),
              if (!e.tapBetweenSets)
                NumberStepper(
                  label: 'Rest',
                  unit: 's',
                  value: e.restBetweenSets,
                  onChanged: (v) =>
                      _set(e.copyWithCommon(restBetweenSets: v)),
                ),
            ],
            const SizedBox(height: 24),
            Text(
              [
                'Duration ≈ ${formatDuration(estimateExercise(e))}',
                if (e.tapBetweenSets && e.sets > 1)
                  e.sets == 2 ? '+ 1 tap' : '+ ${e.sets - 1} taps',
              ].join(' '),
              textAlign: TextAlign.center,
              style: textTheme.titleMedium,
            ),
          ],
        ),
      ),
      ),
    );
  }

  List<Widget> _holdFields(HoldExercise h) => [
        NumberStepper(
          label: 'Reps',
          value: h.reps,
          min: 1,
          onChanged: (v) => _set(h.copyWith(reps: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Two holds per rep'),
          subtitle: const Text('e.g. Left then Right'),
          value: h.twoHolds,
          onChanged: (v) => _set(h.copyWith(twoHolds: v)),
        ),
        if (!h.twoHolds)
          NumberStepper(
            label: 'Hold',
            unit: 's',
            value: h.holdSeconds,
            min: 1,
            onChanged: (v) => _set(h.copyWith(holdSeconds: v)),
          )
        else ...[
          _holdNameField(_firstHoldName, 'Hold 1 name'),
          NumberStepper(
            label: 'Hold 1',
            unit: 's',
            value: h.holdSeconds,
            min: 1,
            onChanged: (v) => _set(h.copyWith(holdSeconds: v)),
          ),
          const SizedBox(height: 8),
          _holdNameField(_secondHoldName, 'Hold 2 name'),
          NumberStepper(
            label: 'Hold 2',
            unit: 's',
            value: h.secondHoldSeconds,
            min: 1,
            onChanged: (v) => _set(h.copyWith(secondHoldSeconds: v)),
          ),
        ],
        NumberStepper(
          label: h.twoHolds ? 'Rest after each hold' : 'Rest between reps',
          unit: 's',
          value: h.restBetweenReps,
          onChanged: (v) => _set(h.copyWith(restBetweenReps: v)),
        ),
      ];

  Widget _holdNameField(TextEditingController controller, String label) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  List<Widget> _tempoFields(TempoExercise t) => [
        NumberStepper(
          label: 'Reps',
          value: t.reps,
          min: 1,
          onChanged: (v) => _set(t.copyWith(reps: v)),
        ),
        NumberStepper(
          label: 'Move',
          unit: 's',
          value: t.moveSeconds,
          min: 1,
          onChanged: (v) => _set(t.copyWith(moveSeconds: v)),
        ),
        NumberStepper(
          label: 'Hold',
          unit: 's',
          value: t.holdSeconds,
          onChanged: (v) => _set(t.copyWith(holdSeconds: v)),
        ),
        NumberStepper(
          label: 'Return',
          unit: 's',
          value: t.returnSeconds,
          min: 1,
          onChanged: (v) => _set(t.copyWith(returnSeconds: v)),
        ),
      ];
}
