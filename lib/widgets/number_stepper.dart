import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A labelled integer field with big −/+ buttons; tap the value to type it.
class NumberStepper extends StatelessWidget {
  const NumberStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 999,
    this.unit,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  /// Shown after the value, e.g. "s".
  final String? unit;

  Future<void> _type(BuildContext context) async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _NumberDialog(label: label, value: value, unit: unit),
    );
    if (result != null) onChanged(result.clamp(min, max));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: textTheme.bodyLarge)),
          IconButton.filledTonal(
            tooltip: 'Decrease $label',
            iconSize: 28,
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _type(context),
            child: SizedBox(
              width: 72,
              height: 48,
              child: Center(
                child: Text(
                  unit == null ? '$value' : '$value $unit',
                  style: textTheme.titleLarge,
                ),
              ),
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Increase $label',
            iconSize: 28,
            onPressed: value < max ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

/// Owns its controller, so it outlives the dialog's closing animation.
class _NumberDialog extends StatefulWidget {
  const _NumberDialog({required this.label, required this.value, this.unit});

  final String label;
  final int value;
  final String? unit;

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final _controller = TextEditingController(text: '${widget.value}')
    ..selection =
        TextSelection(baseOffset: 0, extentOffset: '${widget.value}'.length);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, int.tryParse(_controller.text));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.label),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(suffixText: widget.unit),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}
