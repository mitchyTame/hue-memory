import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Result of a deskew pass (angle may be 0 when unchanged).
class DeskewResult {
  const DeskewResult({
    required this.bytes,
    required this.mime,
    required this.angleDegrees,
    required this.applied,
  });

  final Uint8List bytes;
  final String mime;
  final double angleDegrees;
  final bool applied;
}

/// Lightweight paper deskew via projection-profile search.
///
/// Flutter-friendly alternative to OpenCV — uses the `image` package only.
/// Searches a small angle window and picks the rotation that maximizes
/// horizontal projection variance (lines become more “peaky” when upright).
class ImageDeskew {
  const ImageDeskew({
    this.maxAbsDegrees = 6.0,
    this.stepDegrees = 0.5,
    this.minAbsDegrees = 0.4,
  });

  final double maxAbsDegrees;
  final double stepDegrees;
  final double minAbsDegrees;

  /// Deskew PNG/JPEG bytes. Returns original bytes when decode fails or the
  /// best angle is below [minAbsDegrees].
  DeskewResult deskewPng(Uint8List bytes, {String mime = 'image/png'}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return DeskewResult(
        bytes: bytes,
        mime: mime,
        angleDegrees: 0,
        applied: false,
      );
    }

    // Work on a small grayscale preview for speed.
    final preview = img.copyResize(
      decoded,
      width: math.min(480, decoded.width),
      maintainAspect: true,
      interpolation: img.Interpolation.average,
    );
    final gray = img.grayscale(preview);

    var bestAngle = 0.0;
    var bestScore = _projectionVariance(gray, 0);
    for (var a = -maxAbsDegrees; a <= maxAbsDegrees + 1e-9; a += stepDegrees) {
      if (a.abs() < 1e-9) continue;
      final score = _projectionVariance(gray, a);
      if (score > bestScore) {
        bestScore = score;
        bestAngle = a;
      }
    }

    if (bestAngle.abs() < minAbsDegrees) {
      return DeskewResult(
        bytes: bytes,
        mime: mime,
        angleDegrees: 0,
        applied: false,
      );
    }

    final rotated = img.copyRotate(
      decoded,
      angle: bestAngle,
      interpolation: img.Interpolation.linear,
    );
    final out = Uint8List.fromList(img.encodePng(rotated));
    return DeskewResult(
      bytes: out,
      mime: 'image/png',
      angleDegrees: bestAngle,
      applied: true,
    );
  }

  static double _projectionVariance(img.Image gray, double angleDegrees) {
    final rotated = angleDegrees.abs() < 1e-9
        ? gray
        : img.copyRotate(
            gray,
            angle: angleDegrees,
            interpolation: img.Interpolation.nearest,
          );
    final h = rotated.height;
    final w = rotated.width;
    if (h < 8 || w < 8) return 0;
    final rowSums = List<double>.filled(h, 0);
    for (var y = 0; y < h; y++) {
      var sum = 0.0;
      for (var x = 0; x < w; x++) {
        // Dark ink → higher weight.
        sum += 255 - rotated.getPixel(x, y).r;
      }
      rowSums[y] = sum;
    }
    final mean = rowSums.reduce((a, b) => a + b) / h;
    var varSum = 0.0;
    for (final v in rowSums) {
      final d = v - mean;
      varSum += d * d;
    }
    return varSum / h;
  }
}
