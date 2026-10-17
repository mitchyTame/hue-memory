import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Crop a normalized `[left, top, width, height]` (0–1) region to PNG bytes.
class ImageCrop {
  const ImageCrop({this.padFraction = 0.04});

  /// Extra padding around the box so handwriting near the border survives.
  final double padFraction;

  Uint8List? cropNorm(
    Uint8List imageBytes, {
    required List<double> bbox,
  }) {
    if (bbox.length < 4) return null;
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return null;

    final pad = padFraction;
    final left = (bbox[0] - pad).clamp(0.0, 1.0);
    final top = (bbox[1] - pad).clamp(0.0, 1.0);
    final right = (bbox[0] + bbox[2] + pad).clamp(0.0, 1.0);
    final bottom = (bbox[1] + bbox[3] + pad).clamp(0.0, 1.0);
    if (right <= left || bottom <= top) return null;

    final x = (left * decoded.width).floor().clamp(0, decoded.width - 1);
    final y = (top * decoded.height).floor().clamp(0, decoded.height - 1);
    final w = math
        .max(8, ((right - left) * decoded.width).ceil())
        .clamp(1, decoded.width - x);
    final h = math
        .max(8, ((bottom - top) * decoded.height).ceil())
        .clamp(1, decoded.height - y);

    final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
    return Uint8List.fromList(img.encodePng(cropped));
  }
}
