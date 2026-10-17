import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:mistralai_dart/mistralai_dart.dart';

import '../writers/mindmap_propose.dart';

/// One proposed mindmap box in normalized 0–1 image space.
class RegionProposal {
  const RegionProposal({
    required this.id,
    required this.bbox,
    this.hintText = '',
    this.source = 'unknown',
  });

  final String id;

  /// `[left, top, width, height]` normalized 0–1.
  final List<double> bbox;
  final String hintText;

  /// `ocr_block` | `contour` | `heuristic`
  final String source;
}

/// Prefer Mistral OCR blocks; else lightweight rectangle contours.
class RegionProposals {
  const RegionProposals({this.maxRegions = MindmapPropose.maxLabels});

  final int maxRegions;

  /// Extract proposals from an [OcrResponse] (blocks preferred).
  List<RegionProposal> fromOcrResponse(
    OcrResponse response, {
    Uint8List? imageBytesForContourFallback,
  }) {
    final fromBlocks = fromOcrBlocks(response);
    if (fromBlocks.isNotEmpty) return fromBlocks;
    if (imageBytesForContourFallback != null) {
      final contours = fromContours(imageBytesForContourFallback);
      if (contours.isNotEmpty) return contours;
    }
    return const [];
  }

  /// Paragraph/title blocks → normalized region proposals.
  List<RegionProposal> fromOcrBlocks(OcrResponse response) {
    final out = <RegionProposal>[];
    for (final page in response.pages) {
      final dims = page.dimensions;
      final pageW = dims?.width ?? 0;
      final pageH = dims?.height ?? 0;
      final blocks = page.blocks;
      if (blocks == null || blocks.isEmpty) continue;
      if (pageW <= 0 || pageH <= 0) continue;

      for (var i = 0; i < blocks.length && out.length < maxRegions; i++) {
        final g = _geom(blocks[i]);
        if (g == null) continue;
        final text = MindmapPropose.clipLabel(g.content);
        if (text.isEmpty) continue;
        // Skip tiny / full-page blocks (headers, page chrome).
        final w = (g.brx - g.tlx) / pageW;
        final h = (g.bry - g.tly) / pageH;
        if (w < 0.04 || h < 0.02) continue;
        if (w > 0.92 && h > 0.5) continue;
        final left = (g.tlx / pageW).clamp(0.0, 1.0);
        final top = (g.tly / pageH).clamp(0.0, 1.0);
        out.add(
          RegionProposal(
            id: 'b${out.length + 1}',
            bbox: [
              left,
              top,
              w.clamp(0.04, 1.0 - left),
              h.clamp(0.02, 1.0 - top),
            ],
            hintText: text,
            source: 'ocr_block',
          ),
        );
      }
    }
    return out;
  }

  /// Lightweight axis-aligned dark-frame detector (no OpenCV).
  ///
  /// Finds mid-sized rectangular ink frames typical of hand-drawn mindmap
  /// boxes. Prototype-quality — prefer OCR blocks when available.
  List<RegionProposal> fromContours(Uint8List imageBytes) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return const [];
    final small = img.copyResize(
      decoded,
      width: math.min(640, decoded.width),
      maintainAspect: true,
      interpolation: img.Interpolation.average,
    );
    final gray = img.grayscale(small);
    final w = gray.width;
    final h = gray.height;
    if (w < 32 || h < 32) return const [];

    // Binary ink mask (dark strokes).
    final ink = List<bool>.filled(w * h, false);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        ink[y * w + x] = gray.getPixel(x, y).r < 140;
      }
    }

    // Horizontal / vertical run edges → candidate rectangles via interior holes.
    final candidates = <RegionProposal>[];
    final visited = List<bool>.filled(w * h, false);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final i = y * w + x;
        if (ink[i] || visited[i]) continue;
        // Flood-fill white interior; if enclosed by ink, keep bbox.
        final box = _floodInterior(ink, visited, w, h, x, y);
        if (box == null) continue;
        final bw = box.$3 - box.$1;
        final bh = box.$4 - box.$2;
        final area = bw * bh;
        if (area < (w * h * 0.008) || area > (w * h * 0.45)) continue;
        final aspect = bw / math.max(1, bh);
        if (aspect < 0.35 || aspect > 6.0) continue;
        // Require some ink on the perimeter (drawn box, not blank page).
        if (_perimeterInkRatio(ink, w, h, box) < 0.12) continue;
        candidates.add(
          RegionProposal(
            id: 'c${candidates.length + 1}',
            bbox: [
              box.$1 / w,
              box.$2 / h,
              bw / w,
              bh / h,
            ],
            source: 'contour',
          ),
        );
        if (candidates.length >= maxRegions) {
          return _scaleToOriginal(candidates, small, decoded);
        }
      }
    }
    return _scaleToOriginal(candidates, small, decoded);
  }

  List<RegionProposal> _scaleToOriginal(
    List<RegionProposal> proposals,
    img.Image small,
    img.Image original,
  ) {
    // Proposals already normalized on [small]; same 0–1 space maps to original.
    return proposals.take(maxRegions).toList(growable: false);
  }

  static ({int tlx, int tly, int brx, int bry, String content})? _geom(
    OcrBlock block,
  ) {
    // Skip chrome; keep label-like content.
    return switch (block) {
      OcrTextBlock(
        :final topLeftX,
        :final topLeftY,
        :final bottomRightX,
        :final bottomRightY,
        :final content,
      ) =>
        (
          tlx: topLeftX,
          tly: topLeftY,
          brx: bottomRightX,
          bry: bottomRightY,
          content: content,
        ),
      OcrTitleBlock(
        :final topLeftX,
        :final topLeftY,
        :final bottomRightX,
        :final bottomRightY,
        :final content,
      ) =>
        (
          tlx: topLeftX,
          tly: topLeftY,
          brx: bottomRightX,
          bry: bottomRightY,
          content: content,
        ),
      OcrListBlock(
        :final topLeftX,
        :final topLeftY,
        :final bottomRightX,
        :final bottomRightY,
        :final content,
      ) =>
        (
          tlx: topLeftX,
          tly: topLeftY,
          brx: bottomRightX,
          bry: bottomRightY,
          content: content,
        ),
      OcrCaptionBlock(
        :final topLeftX,
        :final topLeftY,
        :final bottomRightX,
        :final bottomRightY,
        :final content,
      ) =>
        (
          tlx: topLeftX,
          tly: topLeftY,
          brx: bottomRightX,
          bry: bottomRightY,
          content: content,
        ),
      OcrAsideTextBlock(
        :final topLeftX,
        :final topLeftY,
        :final bottomRightX,
        :final bottomRightY,
        :final content,
      ) =>
        (
          tlx: topLeftX,
          tly: topLeftY,
          brx: bottomRightX,
          bry: bottomRightY,
          content: content,
        ),
      _ => null,
    };
  }

  /// Returns `(minX, minY, maxX, maxY)` for a flooded white interior, or null
  /// if it touches the image border (not enclosed).
  static (int, int, int, int)? _floodInterior(
    List<bool> ink,
    List<bool> visited,
    int w,
    int h,
    int sx,
    int sy,
  ) {
    final stack = <int>[sy * w + sx];
    visited[sy * w + sx] = true;
    var minX = sx, maxX = sx, minY = sy, maxY = sy;
    var touchesBorder = false;
    var count = 0;
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      final x = i % w;
      final y = i ~/ w;
      count++;
      if (count > w * h ~/ 2) return null;
      if (x == 0 || y == 0 || x == w - 1 || y == h - 1) touchesBorder = true;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      for (final (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]) {
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final ni = ny * w + nx;
        if (visited[ni] || ink[ni]) continue;
        visited[ni] = true;
        stack.add(ni);
      }
    }
    if (touchesBorder || count < 40) return null;
    return (minX, minY, maxX, maxY);
  }

  static double _perimeterInkRatio(
    List<bool> ink,
    int w,
    int h,
    (int, int, int, int) box,
  ) {
    final (x0, y0, x1, y1) = box;
    var inkCount = 0;
    var total = 0;
    for (var x = x0; x <= x1; x++) {
      total += 2;
      if (ink[y0 * w + x]) inkCount++;
      if (ink[y1 * w + x]) inkCount++;
    }
    for (var y = y0 + 1; y < y1; y++) {
      total += 2;
      if (ink[y * w + x0]) inkCount++;
      if (ink[y * w + x1]) inkCount++;
    }
    return total == 0 ? 0 : inkCount / total;
  }
}
