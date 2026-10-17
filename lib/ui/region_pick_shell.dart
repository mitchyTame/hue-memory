import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/memory_hues.dart';
import '../vision/l_corner_regions.dart';

/// Pick which L-corner page region to OCR (multi-note A3 pages).
///
/// Pops with the chosen [PageRegion], or `null` to OCR the whole page.
class RegionPickShell extends StatefulWidget {
  const RegionPickShell({
    super.key,
    required this.imageBytes,
    required this.regions,
  });

  final Uint8List imageBytes;
  final List<PageRegion> regions;

  @override
  State<RegionPickShell> createState() => _RegionPickShellState();
}

class _RegionPickShellState extends State<RegionPickShell> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final regions = widget.regions;

    return Scaffold(
      backgroundColor: MemoryHues.fieldDeep,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose note region',
                    style: textTheme.titleLarge?.copyWith(
                      color: MemoryHues.paperElevated,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Four L-corners mark each note. Tap a box, then Continue '
                    'to OCR that crop.',
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
                    return GestureDetector(
                      onTapUp: (details) {
                        final box = context.findRenderObject() as RenderBox?;
                        if (box == null) return;
                        final local = details.localPosition;
                        final size = box.size;
                        final nx = (local.dx / size.width).clamp(0.0, 1.0);
                        final ny = (local.dy / size.height).clamp(0.0, 1.0);
                        for (var i = 0; i < regions.length; i++) {
                          final r = regions[i];
                          if (nx >= r.left &&
                              nx <= r.left + r.width &&
                              ny >= r.top &&
                              ny <= r.top + r.height) {
                            setState(() => _selected = i);
                            return;
                          }
                        }
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            widget.imageBytes,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                          CustomPaint(
                            painter: _RegionOverlayPainter(
                              regions: regions,
                              selected: _selected,
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
                    onPressed: () => Navigator.of(context).pop<PageRegion?>(),
                    child: Text(
                      'Whole page',
                      style: TextStyle(
                        color: MemoryHues.paperElevated.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context)
                        .pop<PageRegion?>(regions[_selected]),
                    child: Text(
                      'OCR region ${_selected + 1}',
                    ),
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

class _RegionOverlayPainter extends CustomPainter {
  const _RegionOverlayPainter({
    required this.regions,
    required this.selected,
  });

  final List<PageRegion> regions;
  final int selected;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < regions.length; i++) {
      final r = regions[i];
      final rect = Rect.fromLTWH(
        r.left * size.width,
        r.top * size.height,
        r.width * size.width,
        r.height * size.height,
      );
      final active = i == selected;
      final fill = Paint()
        ..color = (active ? MemoryHues.accent : MemoryHues.fieldLift)
            .withValues(alpha: active ? 0.22 : 0.12);
      final stroke = Paint()
        ..color = active
            ? MemoryHues.accentSoft
            : MemoryHues.recall.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = active ? 3 : 1.5;
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, stroke);

      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: MemoryHues.paperElevated,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.left + 6, rect.top + 4));
    }
  }

  @override
  bool shouldRepaint(covariant _RegionOverlayPainter oldDelegate) =>
      oldDelegate.selected != selected || oldDelegate.regions != regions;
}
