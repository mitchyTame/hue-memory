import 'dart:typed_data';
import 'dart:ui' as ui;

import 'mistral_ocr_request.dart';

/// Longest edge for OCR uploads — keeps payloads small and reliable.
const int kOcrMaxImageSide = 2048;

/// Longest edge for △ vision structure — sharper handwriting than OCR thumb.
///
/// Still capped for API size; higher than [kOcrMaxImageSide] so box text stays
/// readable for the vision model.
const int kVisionMaxImageSide = 3072;

/// Prepared bytes + MIME ready for a Mistral `image_url` data URL.
typedef PreparedOcrImage = ({Uint8List bytes, String mime});

/// Decode any Flutter-supported image and re-encode as a scaled PNG.
///
/// Always re-encodes when decode succeeds so we never ship a corrupt file that
/// only has a PNG/JPEG magic header (Mistral: "base64 could not be loaded as
/// a valid image"). Undecodable bytes throw — better than a silent 400.
Future<PreparedOcrImage> prepareImageForMistralOcr(
  Uint8List bytes, {
  String? imageMimeType,
  String? extensionHint,
  int maxSide = kOcrMaxImageSide,
}) async {
  if (bytes.isEmpty) {
    throw StateError('Capture has no image bytes');
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

    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (png == null) {
      throw StateError('Could not encode image for OCR');
    }
    return (bytes: png.buffer.asUint8List(), mime: 'image/png');
  } catch (e) {
    final mime = resolveOcrMime(
      bytes,
      imageMimeType: imageMimeType,
      extensionHint: extensionHint,
    );
    throw StateError(
      'Could not decode image for OCR ($mime): $e',
    );
  }
}
