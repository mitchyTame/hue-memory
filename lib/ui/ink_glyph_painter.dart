import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../symbols/ink_library.dart';
import '../theme/memory_hues.dart';

/// Stroke-only CustomPainter for ink-v1 library draw ids.
class InkGlyphPainter extends CustomPainter {
  const InkGlyphPainter({
    required this.drawId,
    this.color = MemoryHues.ink,
    this.strokeWidth = 1.75,
  });

  final String drawId;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;

    switch (drawId) {
      case InkDrawIds.circleOpen:
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, cy), width: w * 0.64, height: h * 0.64),
          paint,
        );
      case InkDrawIds.wave:
        final path = Path()
          ..moveTo(w * 0.12, cy)
          ..quadraticBezierTo(w * 0.28, cy - h * 0.28, w * 0.44, cy)
          ..quadraticBezierTo(w * 0.60, cy + h * 0.28, w * 0.76, cy)
          ..quadraticBezierTo(w * 0.84, cy - h * 0.12, w * 0.88, cy);
        canvas.drawPath(path, paint);
      case InkDrawIds.tripleBar:
        for (final t in [0.28, 0.5, 0.72]) {
          final y = h * t;
          canvas.drawLine(Offset(w * 0.18, y), Offset(w * 0.82, y), paint);
        }
      case InkDrawIds.diamond:
        final path = Path()
          ..moveTo(cx, h * 0.12)
          ..lineTo(w * 0.82, cy)
          ..lineTo(cx, h * 0.88)
          ..lineTo(w * 0.18, cy)
          ..close();
        canvas.drawPath(path, paint);
      case InkDrawIds.triangle:
        final path = Path()
          ..moveTo(cx, h * 0.14)
          ..lineTo(w * 0.84, h * 0.82)
          ..lineTo(w * 0.16, h * 0.82)
          ..close();
        canvas.drawPath(path, paint);
      case InkDrawIds.dot:
        final fill = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(cx, cy), math.min(w, h) * 0.12, fill);
      case InkDrawIds.dash:
        canvas.drawLine(
          Offset(w * 0.22, cy),
          Offset(w * 0.78, cy),
          paint,
        );
      case InkDrawIds.bar:
        // Simple stem for Journal (glyph on paper is the letter J).
        canvas.drawLine(
          Offset(cx, h * 0.14),
          Offset(cx, h * 0.72),
          paint,
        );
        canvas.drawArc(
          Rect.fromLTWH(w * 0.28, h * 0.55, w * 0.36, h * 0.28),
          0,
          math.pi,
          false,
          paint,
        );
      case InkDrawIds.squareOpen:
        canvas.drawRect(
          Rect.fromCenter(center: Offset(cx, cy), width: w * 0.58, height: h * 0.58),
          paint,
        );
      case InkDrawIds.arrow:
        canvas.drawLine(Offset(w * 0.18, cy), Offset(w * 0.78, cy), paint);
        final head = Path()
          ..moveTo(w * 0.58, cy - h * 0.18)
          ..lineTo(w * 0.82, cy)
          ..lineTo(w * 0.58, cy + h * 0.18);
        canvas.drawPath(head, paint);
      case InkDrawIds.cross:
        canvas.drawLine(
          Offset(w * 0.28, h * 0.28),
          Offset(w * 0.72, h * 0.72),
          paint,
        );
        canvas.drawLine(
          Offset(w * 0.72, h * 0.28),
          Offset(w * 0.28, h * 0.72),
          paint,
        );
      case InkDrawIds.plus:
        canvas.drawLine(Offset(cx, h * 0.22), Offset(cx, h * 0.78), paint);
        canvas.drawLine(Offset(w * 0.22, cy), Offset(w * 0.78, cy), paint);
      case InkDrawIds.asterisk:
        for (final a in [0.0, math.pi / 3, 2 * math.pi / 3]) {
          final dx = math.cos(a) * w * 0.32;
          final dy = math.sin(a) * h * 0.32;
          canvas.drawLine(
            Offset(cx - dx, cy - dy),
            Offset(cx + dx, cy + dy),
            paint,
          );
        }
      case InkDrawIds.halfCircle:
        canvas.drawArc(
          Rect.fromCenter(center: Offset(cx, cy), width: w * 0.64, height: h * 0.64),
          -math.pi / 2,
          math.pi,
          false,
          paint,
        );
        canvas.drawLine(
          Offset(cx, cy - h * 0.32),
          Offset(cx, cy + h * 0.32),
          paint,
        );
      case InkDrawIds.chevron:
        final path = Path()
          ..moveTo(w * 0.32, h * 0.22)
          ..lineTo(w * 0.68, cy)
          ..lineTo(w * 0.32, h * 0.78);
        canvas.drawPath(path, paint);
      case InkDrawIds.hook:
        final path = Path()
          ..moveTo(w * 0.62, h * 0.22)
          ..quadraticBezierTo(w * 0.22, cy, w * 0.55, h * 0.78);
        canvas.drawPath(path, paint);
        canvas.drawLine(
          Offset(w * 0.42, h * 0.62),
          Offset(w * 0.72, h * 0.62),
          paint,
        );
      case InkDrawIds.corner:
        canvas.drawLine(
          Offset(w * 0.28, h * 0.28),
          Offset(w * 0.72, h * 0.28),
          paint,
        );
        canvas.drawLine(
          Offset(w * 0.28, h * 0.28),
          Offset(w * 0.28, h * 0.72),
          paint,
        );
      case InkDrawIds.circleDot:
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, cy), width: w * 0.64, height: h * 0.64),
          paint,
        );
        final fill = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(cx, cy), math.min(w, h) * 0.08, fill);
      case InkDrawIds.invTriangle:
        final path = Path()
          ..moveTo(w * 0.16, h * 0.18)
          ..lineTo(w * 0.84, h * 0.18)
          ..lineTo(cx, h * 0.86)
          ..close();
        canvas.drawPath(path, paint);
      default:
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, cy), width: w * 0.4, height: h * 0.4),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(covariant InkGlyphPainter oldDelegate) =>
      oldDelegate.drawId != drawId ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
