import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/hue_atmosphere.dart';
import '../theme/memory_hues.dart';
import '../vision/page_region.dart';

/// Optional OCR crop after shutter.
///
/// Pops with a [PageRegion] to OCR that crop, or `null` for whole-page OCR.
class ManualRegionShell extends StatefulWidget {
  const ManualRegionShell({
    super.key,
    required this.imageBytes,
  });

  final Uint8List imageBytes;

  @override
  State<ManualRegionShell> createState() => _ManualRegionShellState();
}

enum _DragMode { none, draw, move, resize }

enum _Handle { tl, tr, bl, br }

class _ManualRegionShellState extends State<ManualRegionShell> {
  ui.Image? _decoded;
  /// Normalized rect in image space: left, top, width, height (0–1), or null.
  Rect? _norm;
  _DragMode _mode = _DragMode.none;
  _Handle? _handle;
  Offset? _drawStartNorm;
  Offset? _moveStartNorm;
  Rect? _moveStartRect;

  static const _minNorm = 0.08;
  static const _handleHit = 28.0;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void dispose() {
    _decoded?.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    final codec = await ui.instantiateImageCodec(widget.imageBytes);
    final frame = await codec.getNextFrame();
    if (!mounted) {
      frame.image.dispose();
      return;
    }
    setState(() {
      _decoded?.dispose();
      _decoded = frame.image;
    });
  }

  Rect? _contentRect(Size box) {
    final img = _decoded;
    if (img == null || img.width <= 0 || img.height <= 0) return null;
    return _containRect(
      box,
      Size(img.width.toDouble(), img.height.toDouble()),
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

  Offset? _toNorm(Offset local, Rect content) {
    if (!content.contains(local)) return null;
    return Offset(
      ((local.dx - content.left) / content.width).clamp(0.0, 1.0),
      ((local.dy - content.top) / content.height).clamp(0.0, 1.0),
    );
  }

  Rect _normToLocal(Rect norm, Rect content) {
    return Rect.fromLTWH(
      content.left + norm.left * content.width,
      content.top + norm.top * content.height,
      norm.width * content.width,
      norm.height * content.height,
    );
  }

  _Handle? _hitHandle(Offset local, Rect content) {
    final norm = _norm;
    if (norm == null) return null;
    final box = _normToLocal(norm, content);
    final points = <_Handle, Offset>{
      _Handle.tl: box.topLeft,
      _Handle.tr: box.topRight,
      _Handle.bl: box.bottomLeft,
      _Handle.br: box.bottomRight,
    };
    for (final e in points.entries) {
      if ((e.value - local).distance <= _handleHit) return e.key;
    }
    return null;
  }

  Rect _clampNorm(Rect r) {
    var left = r.left.clamp(0.0, 1.0 - _minNorm);
    var top = r.top.clamp(0.0, 1.0 - _minNorm);
    var width = r.width.clamp(_minNorm, 1.0 - left);
    var height = r.height.clamp(_minNorm, 1.0 - top);
    if (left + width > 1.0) width = 1.0 - left;
    if (top + height > 1.0) height = 1.0 - top;
    return Rect.fromLTWH(left, top, width, height);
  }

  void _onPanStart(DragStartDetails d, Rect content) {
    final local = d.localPosition;
    final handle = _hitHandle(local, content);
    if (handle != null && _norm != null) {
      setState(() {
        _mode = _DragMode.resize;
        _handle = handle;
      });
      return;
    }
    final normPt = _toNorm(local, content);
    if (normPt == null) return;
    if (_norm != null && _norm!.contains(normPt)) {
      setState(() {
        _mode = _DragMode.move;
        _moveStartNorm = normPt;
        _moveStartRect = _norm;
      });
      return;
    }
    setState(() {
      _mode = _DragMode.draw;
      _drawStartNorm = normPt;
      _norm = Rect.fromLTWH(normPt.dx, normPt.dy, _minNorm, _minNorm);
    });
  }

  void _onPanUpdate(DragUpdateDetails d, Rect content) {
    final local = d.localPosition;
    final normPt = _toNorm(
      Offset(
        local.dx.clamp(content.left, content.right),
        local.dy.clamp(content.top, content.bottom),
      ),
      content,
    );
    if (normPt == null) return;

    if (_mode == _DragMode.draw && _drawStartNorm != null) {
      final a = _drawStartNorm!;
      final left = a.dx < normPt.dx ? a.dx : normPt.dx;
      final top = a.dy < normPt.dy ? a.dy : normPt.dy;
      final right = a.dx < normPt.dx ? normPt.dx : a.dx;
      final bottom = a.dy < normPt.dy ? normPt.dy : a.dy;
      setState(() {
        _norm = _clampNorm(
          Rect.fromLTRB(left, top, right.clamp(left + _minNorm, 1.0),
              bottom.clamp(top + _minNorm, 1.0)),
        );
      });
      return;
    }

    if (_mode == _DragMode.move &&
        _moveStartNorm != null &&
        _moveStartRect != null) {
      final dx = normPt.dx - _moveStartNorm!.dx;
      final dy = normPt.dy - _moveStartNorm!.dy;
      final s = _moveStartRect!;
      setState(() {
        _norm = _clampNorm(
          Rect.fromLTWH(s.left + dx, s.top + dy, s.width, s.height),
        );
      });
      return;
    }

    if (_mode == _DragMode.resize && _norm != null && _handle != null) {
      var left = _norm!.left;
      var top = _norm!.top;
      var right = _norm!.right;
      var bottom = _norm!.bottom;
      switch (_handle!) {
        case _Handle.tl:
          left = normPt.dx;
          top = normPt.dy;
        case _Handle.tr:
          right = normPt.dx;
          top = normPt.dy;
        case _Handle.bl:
          left = normPt.dx;
          bottom = normPt.dy;
        case _Handle.br:
          right = normPt.dx;
          bottom = normPt.dy;
      }
      final nLeft = left < right ? left : right;
      final nRight = left < right ? right : left;
      final nTop = top < bottom ? top : bottom;
      final nBottom = top < bottom ? bottom : top;
      setState(() {
        _norm = _clampNorm(Rect.fromLTRB(nLeft, nTop, nRight, nBottom));
      });
    }
  }

  void _onPanEnd(DragEndDetails _) {
    setState(() {
      _mode = _DragMode.none;
      _handle = null;
      _drawStartNorm = null;
      _moveStartNorm = null;
      _moveStartRect = null;
    });
  }

  void _clearRegion() => setState(() => _norm = null);

  void _useWholePage() => Navigator.of(context).pop<PageRegion?>();

  void _useRegion() {
    final n = _norm;
    if (n == null) return;
    Navigator.of(context).pop<PageRegion?>(
      PageRegion.manual(
        left: n.left,
        top: n.top,
        width: n.width,
        height: n.height,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasRegion = _norm != null;

    return HueFieldScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Frame OCR region',
                    style: textTheme.titleLarge?.copyWith(
                      color: MemoryHues.paperElevated,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasRegion
                        ? 'Drag the box to move · corners to resize. '
                            'Or use whole page.'
                        : 'Drag on the photo to frame one note. '
                            'Or skip for whole-page OCR.',
                    style: textTheme.bodySmall?.copyWith(
                      color: MemoryHues.paperElevated.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final box = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    final content = _contentRect(box);
                    return GestureDetector(
                      onPanStart: content == null
                          ? null
                          : (d) => _onPanStart(d, content),
                      onPanUpdate: content == null
                          ? null
                          : (d) => _onPanUpdate(d, content),
                      onPanEnd: _onPanEnd,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            widget.imageBytes,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                          if (content != null)
                            CustomPaint(
                              painter: _ManualRegionPainter(
                                contentRect: content,
                                norm: _norm,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _useWholePage,
                    style: TextButton.styleFrom(
                      foregroundColor:
                          MemoryHues.paperElevated.withValues(alpha: 0.9),
                    ),
                    child: const Text('Use whole page'),
                  ),
                  if (hasRegion) ...[
                    TextButton(
                      onPressed: _clearRegion,
                      style: TextButton.styleFrom(
                        foregroundColor:
                            MemoryHues.paperElevated.withValues(alpha: 0.65),
                      ),
                      child: const Text('Clear'),
                    ),
                  ],
                  const Spacer(),
                  FilledButton(
                    onPressed: hasRegion ? _useRegion : null,
                    child: const Text('OCR this region'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualRegionPainter extends CustomPainter {
  const _ManualRegionPainter({
    required this.contentRect,
    required this.norm,
  });

  final Rect contentRect;
  final Rect? norm;

  @override
  void paint(Canvas canvas, Size size) {
    // Dim outside the crop when a region exists.
    if (norm != null) {
      final box = Rect.fromLTWH(
        contentRect.left + norm!.left * contentRect.width,
        contentRect.top + norm!.top * contentRect.height,
        norm!.width * contentRect.width,
        norm!.height * contentRect.height,
      );
      final scrim = Path()
        ..addRect(contentRect)
        ..addRect(box)
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(
        scrim,
        Paint()..color = MemoryHues.overlayScrim,
      );
      canvas.drawRect(
        box,
        Paint()
          ..color = MemoryHues.accentSoft.withValues(alpha: 0.18)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        box,
        Paint()
          ..color = MemoryHues.accentSoft
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      const handleR = 7.0;
      for (final p in [box.topLeft, box.topRight, box.bottomLeft, box.bottomRight]) {
        canvas.drawCircle(
          p,
          handleR,
          Paint()..color = MemoryHues.paperElevated,
        );
        canvas.drawCircle(
          p,
          handleR,
          Paint()
            ..color = MemoryHues.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    } else {
      // Light guide border on the photo area.
      canvas.drawRect(
        contentRect.deflate(1),
        Paint()
          ..color = MemoryHues.paperElevated.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ManualRegionPainter oldDelegate) =>
      oldDelegate.contentRect != contentRect || oldDelegate.norm != norm;
}
