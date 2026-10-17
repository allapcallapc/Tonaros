import 'dart:math';

import 'package:flutter/material.dart';

/// A circular ring that drains clockwise from 12 o'clock as [fractionLeft]
/// goes from 1 to 0, with [child] in the middle.
class PhaseRing extends StatelessWidget {
  const PhaseRing({
    super.key,
    required this.fractionLeft,
    required this.color,
    required this.child,
    this.strokeWidth = 18,
  });

  final double fractionLeft;
  final Color color;
  final double strokeWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _RingPainter(
          fractionLeft: fractionLeft,
          color: color,
          trackColor: color.withValues(alpha: 0.15),
          strokeWidth: strokeWidth,
        ),
        child: Padding(
          padding: EdgeInsets.all(strokeWidth * 2),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fractionLeft,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double fractionLeft;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * pi, false, paint..color = trackColor);
    if (fractionLeft > 0) {
      // The arc's start moves clockwise, so the ring drains the way a clock
      // hand sweeps.
      final sweep = 2 * pi * fractionLeft;
      canvas.drawArc(
          rect, -pi / 2 + (2 * pi - sweep), sweep, false, paint..color = color);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fractionLeft != fractionLeft ||
      old.color != color ||
      old.trackColor != trackColor ||
      old.strokeWidth != strokeWidth;
}
