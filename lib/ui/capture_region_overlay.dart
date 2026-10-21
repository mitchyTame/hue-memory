import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../capture/region_feedback.dart';
import '../theme/memory_hues.dart';
import '../vision/page_region.dart';

/// Transparent OCR-region overlay on the confirm photo preview.
///
/// Teal accent box = manual crop used for OCR; muted whole-page frame when
/// skipped. Never baked into vault bytes.
class CaptureRegionOverlay extends StatefulWidget {
  const CaptureRegionOverlay({
    super.key,
    required this.imageBytes,
    required this.feedback,
    this.child,
  });

  final Uint8List imageBytes;
  final CaptureRegionFeedback feedback;
  final Widget? child;

  @override
  State<CaptureRegionOverlay> createState() => _CaptureRegionOverlayState();
}

class _CaptureRegionOverlayState extends State<CaptureRegionOverlay> {
  ui.Image? _decoded;
  int? _decodeToken;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(covariant CaptureRegionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.imageBytes, widget.imageBytes)) {
      _decode();
    }
  }

  @override
  void dispose() {
    _decoded?.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    final token = DateTime.now().microsecondsSinceEpoch;
    _decodeToken = token;
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    if (!mounted || _decodeToken != token) {
      frame.image.dispose();
      return;
    }
    setState(() {
      _decoded?.dispose();
      _decoded = frame.image;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final img = _decoded;
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        Rect? content;
        if (img != null && img.width > 0 && img.height > 0) {
          content = _containRect(
            Size(w, h),
            Size(img.width.toDouble(), img.height.toDouble()),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            if (widget.child != null) widget.child!,
            if (content != null && !widget.feedback.skippedForDiagram)
              CustomPaint(
                painter: _RegionFeedbackPainter(
                  contentRect: content,
                  feedback: widget.feedback,
                ),
              ),
          ],
        );
      },
    );
  }

  static Rect _containRect(Size box, Size image) {
    final scale = (box.width / image.width < box.height / image.height)
        ? box.width / image.width
        : box.height / image.height;
    final w = image.width * scale;
    final h = image.height * scale;
    return Rect.fromLTWH(
      (box.width - w) / 2,
      (box.height - h) / 2,
      w,
      h,
    );
  }
}

class _RegionFeedbackPainter extends CustomPainter {
  const _RegionFeedbackPainter({
    required this.contentRect,
    required this.feedback,
  });

  final Rect contentRect;
  final CaptureRegionFeedback feedback;

  @override
  void paint(Canvas canvas, Size size) {
    final region = feedback.ocrRegion;
    if (region != null) {
      _paintRegion(canvas, region, color: MemoryHues.accent, active: true);
      _paintBadge(canvas, 'Region OCR', color: MemoryHues.accent);
      return;
    }

    // Whole page — optional skip, not an error.
    final stroke = Paint()
      ..color = MemoryHues.inkMuted.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final inset = contentRect.deflate(6);
    canvas.drawRect(inset, stroke);
    _paintBadge(canvas, 'Whole page OCR', color: MemoryHues.inkMuted);
  }

  void _paintRegion(
    Canvas canvas,
    PageRegion region, {
    required Color color,
    required bool active,
  }) {
    final rect = Rect.fromLTWH(
      contentRect.left + region.left * contentRect.width,
      contentRect.top + region.top * contentRect.height,
      region.width * contentRect.width,
      region.height * contentRect.height,
    );
    canvas.drawRect(
      rect,
      Paint()..color = color.withValues(alpha: active ? 0.22 : 0.1),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = color.withValues(alpha: active ? 0.95 : 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 3 : 1.5,
    );
  }

  void _paintBadge(Canvas canvas, String label, {required Color color}) {
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: MemoryHues.paperElevated,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          shadows: const [
            Shadow(color: Color(0x99000000), blurRadius: 4),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: contentRect.width - 16);
    final bg = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        contentRect.left + 8,
        contentRect.top + 8,
        tp.width + 14,
        tp.height + 8,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      bg,
      Paint()..color = color.withValues(alpha: 0.82),
    );
    tp.paint(canvas, Offset(contentRect.left + 15, contentRect.top + 12));
  }

  @override
  bool shouldRepaint(covariant _RegionFeedbackPainter oldDelegate) =>
      oldDelegate.contentRect != contentRect ||
      oldDelegate.feedback != feedback;
}
