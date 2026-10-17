import 'package:flutter/material.dart';

/// One dot per rep: filled when done, half-filled for a two-hold rep whose
/// first hold is done, outlined ring on the current rep. Square dots for
/// Tempo exercises.
class RepDots extends StatelessWidget {
  const RepDots({
    super.key,
    required this.reps,
    required this.repsDone,
    required this.color,
    this.square = false,
  });

  final int reps;

  /// Completed reps; a .5 marks a half-done rep.
  final double repsDone;
  final Color color;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final size = reps <= 12 ? 20.0 : (reps <= 20 ? 16.0 : 12.0);
    final full = repsDone.floor();
    final current = full + 1;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: size * 0.5,
      runSpacing: size * 0.5,
      children: [
        for (var i = 1; i <= reps; i++)
          Semantics(
            label: i <= full
                ? 'Rep $i done'
                : i == current
                    ? 'Rep $i, current'
                    : 'Rep $i',
            child: CustomPaint(
              size: Size.square(size),
              painter: _DotPainter(
                fill: i <= full
                    ? 1
                    : i == current
                        ? repsDone - full
                        : 0,
                current: i == current,
                color: color,
                square: square,
              ),
            ),
          ),
      ],
    );
  }
}

class _DotPainter extends CustomPainter {
  _DotPainter({
    required this.fill,
    required this.current,
    required this.color,
    required this.square,
  });

  /// 0, 0.5 or 1.
  final double fill;
  final bool current;
  final Color color;
  final bool square;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.14;
    final outer = Offset.zero & size;
    final inner = outer.deflate(stroke / 2);
    void drawShape(Rect r, Paint p) => square
        ? canvas.drawRRect(
            RRect.fromRectAndRadius(r, Radius.circular(size.width * 0.2)), p)
        : canvas.drawOval(r, p);

    if (fill > 0) {
      canvas.save();
      // Fill from the left: half a dot after a two-hold rep's first hold.
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * fill, size.height));
      drawShape(outer, Paint()..color = color);
      canvas.restore();
    }
    if (fill < 1) {
      drawShape(
        inner,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = current ? color : color.withValues(alpha: 0.3),
      );
    }
  }

  @override
  bool shouldRepaint(_DotPainter old) =>
      old.fill != fill ||
      old.current != current ||
      old.color != color ||
      old.square != square;
}
