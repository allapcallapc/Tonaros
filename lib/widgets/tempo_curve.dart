import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/phase_colors.dart';

/// A Tempo rep drawn as its movement profile: rising for the move, flat for
/// the hold, falling for the return, each segment as wide as its share of
/// the rep's time. Segments fill in their phase color as the rep goes on,
/// and a marker glides along the curve at [progress].
class TempoCurve extends StatelessWidget {
  const TempoCurve({
    super.key,
    required this.moveSeconds,
    required this.holdSeconds,
    required this.returnSeconds,
    required this.progress,
  });

  final int moveSeconds;
  final int holdSeconds;
  final int returnSeconds;

  /// How far through the rep, 0 (start of the move) to 1 (end of the
  /// return), by time.
  final double progress;

  /// [progress] at [fractionDone] of the move (0), hold (1) or return (2).
  static double progressAt({
    required int segment,
    required double fractionDone,
    required int moveSeconds,
    required int holdSeconds,
    required int returnSeconds,
  }) {
    final total = moveSeconds + holdSeconds + returnSeconds;
    if (total == 0) return 0;
    final before = [0, moveSeconds, moveSeconds + holdSeconds][segment];
    final length = [moveSeconds, holdSeconds, returnSeconds][segment];
    return (before + fractionDone * length) / total;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label:
          'Tempo: move $moveSeconds s, hold $holdSeconds s, '
          'return $returnSeconds s',
      child: CustomPaint(
        size: Size.infinite,
        painter: _TempoCurvePainter(
          seconds: [moveSeconds, holdSeconds, returnSeconds],
          progress: progress.clamp(0.0, 1.0),
          labelStyle: theme.textTheme.labelLarge!.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          baselineColor: theme.colorScheme.outlineVariant,
          markerFill: theme.colorScheme.surface,
        ),
      ),
    );
  }
}

class _TempoCurvePainter extends CustomPainter {
  _TempoCurvePainter({
    required this.seconds,
    required this.progress,
    required this.labelStyle,
    required this.baselineColor,
    required this.markerFill,
  });

  /// Move, hold, return.
  final List<int> seconds;
  final double progress;
  final TextStyle labelStyle;
  final Color baselineColor;
  final Color markerFill;

  static const _colors = [
    PhaseColors.move,
    PhaseColors.tempoHold,
    PhaseColors.back,
  ];
  static const _labels = ['Move', 'Hold', 'Return'];

  @override
  void paint(Canvas canvas, Size size) {
    final labelHeight = (labelStyle.fontSize ?? 14) * 1.6;
    const stroke = 12.0;
    const markerRadius = 11.0;
    final left = markerRadius + 4;
    final right = size.width - markerRadius - 4;
    final top = labelHeight + markerRadius;
    final bottom = size.height - labelHeight - markerRadius;
    if (right <= left || bottom <= top) return;

    // Widths by share of time, with sloped segments never so narrow that
    // they turn vertical.
    final total = seconds.fold(0, (a, b) => a + b);
    final shares = [
      for (var i = 0; i < 3; i++)
        seconds[i] == 0 ? 0.0 : max(seconds[i] / total, i == 1 ? 0.0 : 0.12),
    ];
    final sum = shares.fold(0.0, (a, b) => a + b);
    final widths = [for (final s in shares) (right - left) * s / sum];
    final points = [
      Offset(left, bottom),
      Offset(left + widths[0], top),
      Offset(left + widths[0] + widths[1], top),
      Offset(right, bottom),
    ];

    // Dashed baseline.
    final dash = Paint()
      ..color = baselineColor
      ..strokeWidth = 1.5;
    for (var x = left; x < right; x += 10) {
      canvas.drawLine(
        Offset(x, bottom),
        Offset(min(x + 5, right), bottom),
        dash,
      );
    }

    // Which segment the marker is on, and how far along it - by time, so
    // a 0 s hold is skipped and the marker moves at the rep's real pace.
    var elapsed = progress * total;
    var markerSegment = 0;
    var markerFraction = 0.0;
    for (var i = 0; i < 3; i++) {
      if (seconds[i] == 0) continue;
      markerSegment = i;
      if (elapsed <= seconds[i]) {
        markerFraction = elapsed / seconds[i];
        break;
      }
      elapsed -= seconds[i];
      markerFraction = 1;
    }

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      if (seconds[i] == 0) continue;
      final a = points[i], b = points[i + 1];
      canvas.drawLine(a, b, line..color = _colors[i].withValues(alpha: 0.28));
      final done = i < markerSegment
          ? 1.0
          : i == markerSegment
          ? markerFraction
          : 0.0;
      if (done > 0 && progress > 0) {
        canvas.drawLine(a, Offset.lerp(a, b, done)!, line..color = _colors[i]);
      }
    }

    // Labels: move and return below their segment, hold above it.
    for (var i = 0; i < 3; i++) {
      if (seconds[i] == 0) continue;
      final mid = Offset.lerp(points[i], points[i + 1], 0.5)!;
      final painter = TextPainter(
        text: TextSpan(
          text: '${_labels[i]} ${seconds[i]}s',
          style: labelStyle.copyWith(
            color: i == markerSegment && progress > 0 ? _colors[i] : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final y = i == 1
          ? top - markerRadius - painter.height - 2
          : bottom + markerRadius + 2;
      final x = (mid.dx - painter.width / 2).clamp(
        0.0,
        max(0.0, size.width - painter.width),
      );
      painter.paint(canvas, Offset(x.toDouble(), y));
    }

    // The marker.
    final at = Offset.lerp(
      points[markerSegment],
      points[markerSegment + 1],
      markerFraction,
    )!;
    final markerColor = progress > 0 ? _colors[markerSegment] : baselineColor;
    canvas.drawCircle(at, markerRadius, Paint()..color = markerFill);
    canvas.drawCircle(
      at,
      markerRadius - 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = markerColor,
    );
  }

  @override
  bool shouldRepaint(_TempoCurvePainter old) =>
      old.progress != progress ||
      old.labelStyle != labelStyle ||
      old.baselineColor != baselineColor ||
      old.markerFill != markerFill ||
      !listEquals(old.seconds, seconds);
}
