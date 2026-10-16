import 'package:flutter/material.dart';

import '../ocr/ocr_client.dart';
import '../theme/memory_hues.dart';

/// Hairline region rects over the page photo (Memory hues — no glow).
class RegionOverlayPainter extends CustomPainter {
  RegionOverlayPainter({
    required this.regions,
    this.lowConfidenceThreshold = 0.85,
  });

  final List<OcrRegion> regions;
  final double lowConfidenceThreshold;

  @override
  void paint(Canvas canvas, Size size) {
    for (final region in regions) {
      final bbox = region.bbox;
      if (bbox == null || bbox.length < 4) continue;

      final rect = Rect.fromLTWH(
        bbox[0] * size.width,
        bbox[1] * size.height,
        bbox[2] * size.width,
        bbox[3] * size.height,
      );

      final low = region.confidence < lowConfidenceThreshold;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = low ? MemoryHues.confidence : MemoryHues.ink;

      if (low) {
        _drawDashedRect(canvas, rect, paint);
      } else {
        canvas.drawRect(rect, paint);
      }
    }
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dash = 6.0;
    const gap = 4.0;
    _dashLine(canvas, rect.topLeft, rect.topRight, paint, dash, gap);
    _dashLine(canvas, rect.topRight, rect.bottomRight, paint, dash, gap);
    _dashLine(canvas, rect.bottomRight, rect.bottomLeft, paint, dash, gap);
    _dashLine(canvas, rect.bottomLeft, rect.topLeft, paint, dash, gap);
  }

  void _dashLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint,
    double dash,
    double gap,
  ) {
    final delta = b - a;
    final length = delta.distance;
    if (length == 0) return;
    final dir = delta / length;
    var drawn = 0.0;
    while (drawn < length) {
      final start = a + dir * drawn;
      final end = a + dir * (drawn + dash).clamp(0, length);
      canvas.drawLine(start, end, paint);
      drawn += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant RegionOverlayPainter oldDelegate) {
    return oldDelegate.regions != regions ||
        oldDelegate.lowConfidenceThreshold != lowConfidenceThreshold;
  }
}
