import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// One note region defined by four ink L-corners (normalized 0–1 bbox).
class PageRegion {
  const PageRegion({
    required this.id,
    required this.bbox,
  });

  final String id;

  /// `[left, top, width, height]` in normalized image space.
  final List<double> bbox;

  double get left => bbox[0];
  double get top => bbox[1];
  double get width => bbox[2];
  double get height => bbox[3];
}

enum _CornerKind { tl, tr, bl, br }

class _LHit {
  const _LHit(this.kind, this.x, this.y);

  final _CornerKind kind;
  final double x;
  final double y;
}

/// Detects rectangular page regions marked by four hand-drawn L-corners.
///
/// L marks are **not** vault routing symbols — they only bound OCR crops
/// (e.g. two notes on an A3 page).
class LCornerRegionDetector {
  const LCornerRegionDetector({
    this.maxSide = 720,
    this.inkThreshold = 145,
  });

  final int maxSide;
  final int inkThreshold;

  /// Returns 0+ regions sorted top-to-bottom, left-to-right.
  List<PageRegion> detect(Uint8List imageBytes) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return const [];

    final small = img.copyResize(
      decoded,
      width: math.min(maxSide, decoded.width),
      maintainAspect: true,
      interpolation: img.Interpolation.average,
    );
    final gray = img.grayscale(small);
    final w = gray.width;
    final h = gray.height;
    if (w < 48 || h < 48) return const [];

    final ink = List<bool>.filled(w * h, false);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        ink[y * w + x] = gray.getPixel(x, y).r < inkThreshold;
      }
    }

    final hits = <_LHit>[];
    final step = math.max(1, math.min(w, h) ~/ 160);
    final arm = math.max(8, math.min(w, h) ~/ 24);
    for (var y = arm; y < h - arm; y += step) {
      for (var x = arm; x < w - arm; x += step) {
        if (!ink[y * w + x]) continue;
        final kind = _classifyCorner(ink, w, h, x, y, arm);
        if (kind == null) continue;
        // Dedup nearby hits of the same kind.
        final nx = x / w;
        final ny = y / h;
        final near = hits.any(
          (h) =>
              h.kind == kind &&
              (h.x - nx).abs() < 0.04 &&
              (h.y - ny).abs() < 0.04,
        );
        if (near) continue;
        hits.add(_LHit(kind, nx, ny));
      }
    }
    if (hits.length < 4) return const [];

    final tls = hits.where((c) => c.kind == _CornerKind.tl).toList();
    final trs = hits.where((c) => c.kind == _CornerKind.tr).toList();
    final bls = hits.where((c) => c.kind == _CornerKind.bl).toList();
    final brs = hits.where((c) => c.kind == _CornerKind.br).toList();
    if (tls.isEmpty || trs.isEmpty || bls.isEmpty || brs.isEmpty) {
      return const [];
    }

    final regions = <PageRegion>[];
    final used = <String>{};
    for (final tl in tls) {
      _LHit? bestTr;
      var bestTrScore = double.infinity;
      for (final tr in trs) {
        if (tr.x <= tl.x + 0.05) continue;
        final dy = (tr.y - tl.y).abs();
        if (dy > 0.08) continue;
        final score = dy + (tr.x - tl.x) * 0.01;
        if (score < bestTrScore) {
          bestTrScore = score;
          bestTr = tr;
        }
      }
      if (bestTr == null) continue;

      _LHit? bestBl;
      var bestBlScore = double.infinity;
      for (final bl in bls) {
        if (bl.y <= tl.y + 0.05) continue;
        final dx = (bl.x - tl.x).abs();
        if (dx > 0.08) continue;
        final score = dx + (bl.y - tl.y) * 0.01;
        if (score < bestBlScore) {
          bestBlScore = score;
          bestBl = bl;
        }
      }
      if (bestBl == null) continue;

      _LHit? bestBr;
      var bestBrScore = double.infinity;
      for (final br in brs) {
        if (br.x <= bestBl.x + 0.04) continue;
        if (br.y <= bestTr.y + 0.04) continue;
        final dx = (br.x - bestTr.x).abs();
        final dy = (br.y - bestBl.y).abs();
        if (dx > 0.1 || dy > 0.1) continue;
        final score = dx + dy;
        if (score < bestBrScore) {
          bestBrScore = score;
          bestBr = br;
        }
      }
      if (bestBr == null) continue;

      final left = math.min(tl.x, bestBl.x);
      final top = math.min(tl.y, bestTr.y);
      final right = math.max(bestTr.x, bestBr.x);
      final bottom = math.max(bestBl.y, bestBr.y);
      final width = right - left;
      final height = bottom - top;
      if (width < 0.12 || height < 0.1) continue;
      if (width > 0.98 || height > 0.98) continue;

      final key =
          '${left.toStringAsFixed(2)}:${top.toStringAsFixed(2)}:'
          '${width.toStringAsFixed(2)}:${height.toStringAsFixed(2)}';
      if (used.contains(key)) continue;
      // Reject heavy overlap with an existing region.
      var overlaps = false;
      for (final r in regions) {
        if (_iou(r.bbox, [left, top, width, height]) > 0.45) {
          overlaps = true;
          break;
        }
      }
      if (overlaps) continue;
      used.add(key);
      regions.add(
        PageRegion(
          id: 'region${regions.length + 1}',
          bbox: [left, top, width, height],
        ),
      );
      if (regions.length >= 8) break;
    }

    regions.sort((a, b) {
      final dy = a.top.compareTo(b.top);
      return dy != 0 ? dy : a.left.compareTo(b.left);
    });
    return regions;
  }

  static _CornerKind? _classifyCorner(
    List<bool> ink,
    int w,
    int h,
    int x,
    int y,
    int arm,
  ) {
    final right = _armInk(ink, w, h, x, y, dx: 1, dy: 0, arm: arm);
    final left = _armInk(ink, w, h, x, y, dx: -1, dy: 0, arm: arm);
    final down = _armInk(ink, w, h, x, y, dx: 0, dy: 1, arm: arm);
    final up = _armInk(ink, w, h, x, y, dx: 0, dy: -1, arm: arm);
    final need = arm * 0.35;
    final weak = arm * 0.28;

    if (right >= need && down >= need && left < weak && up < weak) {
      return _CornerKind.tl;
    }
    if (left >= need && down >= need && right < weak && up < weak) {
      return _CornerKind.tr;
    }
    if (right >= need && up >= need && left < weak && down < weak) {
      return _CornerKind.bl;
    }
    if (left >= need && up >= need && right < weak && down < weak) {
      return _CornerKind.br;
    }
    return null;
  }

  static double _armInk(
    List<bool> ink,
    int w,
    int h,
    int x,
    int y, {
    required int dx,
    required int dy,
    required int arm,
  }) {
    var hits = 0;
    for (var i = 1; i <= arm; i++) {
      final nx = x + dx * i;
      final ny = y + dy * i;
      if (nx < 0 || ny < 0 || nx >= w || ny >= h) break;
      if (ink[ny * w + nx]) hits++;
    }
    return hits.toDouble();
  }

  static double _iou(List<double> a, List<double> b) {
    final ax0 = a[0], ay0 = a[1], ax1 = a[0] + a[2], ay1 = a[1] + a[3];
    final bx0 = b[0], by0 = b[1], bx1 = b[0] + b[2], by1 = b[1] + b[3];
    final ix0 = math.max(ax0, bx0);
    final iy0 = math.max(ay0, by0);
    final ix1 = math.min(ax1, bx1);
    final iy1 = math.min(ay1, by1);
    final iw = ix1 - ix0;
    final ih = iy1 - iy0;
    if (iw <= 0 || ih <= 0) return 0;
    final inter = iw * ih;
    final uni = a[2] * a[3] + b[2] * b[3] - inter;
    return uni <= 0 ? 0 : inter / uni;
  }
}
