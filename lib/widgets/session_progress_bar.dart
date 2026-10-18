import 'package:flutter/material.dart';

/// A hairline bar that fills left to right as [progress] goes from 0 to 1.
/// Meant to sit quietly at the edge of the screen: a faint track, a soft
/// fill in [color] that eases between colors, and a rounded leading edge.
class SessionProgressBar extends StatelessWidget {
  const SessionProgressBar({
    super.key,
    required this.progress,
    required this.color,
    this.height = 3,
  });

  final double progress;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.06);
    return Semantics(
      label: 'Session progress',
      value: '${(progress * 100).round()}%',
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: color),
        duration: const Duration(milliseconds: 400),
        builder: (context, color, _) => CustomPaint(
          size: Size.fromHeight(height),
          painter: _BarPainter(
            progress: progress.clamp(0.0, 1.0),
            color: color!,
            track: track,
          ),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    if (progress <= 0) return;
    final width = size.width * progress;
    final radius = Radius.circular(size.height / 2);
    final fill = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, 0, width, size.height),
      topRight: radius,
      bottomRight: radius,
    );
    canvas.drawRRect(
      fill,
      Paint()
        ..shader = LinearGradient(
          // Scale rather than replace the alpha, so a dimmed color stays
          // dimmed.
          colors: [
            color.withValues(alpha: color.a * 0.25),
            color.withValues(alpha: color.a * 0.8),
          ],
        ).createShader(Rect.fromLTWH(0, 0, width, size.height)),
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}
