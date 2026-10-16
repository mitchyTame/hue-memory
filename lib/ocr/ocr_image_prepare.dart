import 'dart:typed_data';
import 'dart:ui' as ui;

import 'mistral_ocr_request.dart';

/// Longest edge for OCR uploads — keeps payloads small and reliable.
const int kOcrMaxImageSide = 2048;

/// Prepared bytes + MIME ready for a Mistral `image_url` data URL.
typedef PreparedOcrImage = ({Uint8List bytes, String mime});

/// Decode any Flutter-supported image and re-encode as a scaled PNG.
///
/// Test connection uses a tiny PNG successfully; camera JPEGs / gallery HEIC
/// / oversized shots often 400 with a base64-image complaint. Normalizing to
/// PNG (same as the probe) with a bounded size avoids mime mismatch and huge
/// payloads while keeping the same `data:image/png;base64,…` document shape.
Future<PreparedOcrImage> prepareImageForMistralOcr(
  Uint8List bytes, {
  String? imageMimeType,
  String? extensionHint,
  int maxSide = kOcrMaxImageSide,
}) async {
  final fallbackMime = resolveOcrMime(
    bytes,
    imageMimeType: imageMimeType,
    extensionHint: extensionHint,
  );

  if (bytes.isEmpty) {
    return (bytes: bytes, mime: fallbackMime);
  }

  try {
    final probe = await ui.instantiateImageCodec(bytes);
    final probeFrame = await probe.getNextFrame();
    final width = probeFrame.image.width;
    final height = probeFrame.image.height;
    probeFrame.image.dispose();

    int? targetWidth;
    int? targetHeight;
    if (width >= height && width > maxSide) {
      targetWidth = maxSide;
    } else if (height > width && height > maxSide) {
      targetHeight = maxSide;
    }

    // Already a small PNG with correct magic — skip re-encode.
    if (targetWidth == null &&
        targetHeight == null &&
        fallbackMime == 'image/png') {
      return (bytes: bytes, mime: 'image/png');
    }

    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (png == null) {
      return (bytes: bytes, mime: fallbackMime);
    }
    return (bytes: png.buffer.asUint8List(), mime: 'image/png');
  } catch (_) {
    // Undecodable (rare) — send original with best-effort mime.
    return (bytes: bytes, mime: fallbackMime);
  }
}
