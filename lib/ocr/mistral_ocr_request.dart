import 'dart:convert';
import 'dart:typed_data';

import 'image_mime.dart';

/// Normalize MIME for OCR uploads (`image/jpg` → `image/jpeg`).
///
/// Magic bytes win — never label JPEG bytes as PNG (or vice versa).
String resolveOcrMime(
  Uint8List bytes, {
  String? imageMimeType,
  String? extensionHint,
}) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46) {
    return 'image/gif';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }

  final hinted = (imageMimeType ?? '').trim().toLowerCase();
  if (hinted == 'image/jpg' || hinted == 'image/jpeg') return 'image/jpeg';
  if (hinted.startsWith('image/') && hinted.length > 6) return hinted;

  final fromExt = imageMimeTypeOf(bytes, extensionHint: extensionHint);
  if (fromExt == 'image/jpg') return 'image/jpeg';
  return fromExt;
}

/// `data:<mime>;base64,<payload>` — required by Mistral OCR for local images.
String mistralImageDataUrl(Uint8List imageBytes, String mime) {
  final safeMime = mime == 'image/jpg' ? 'image/jpeg' : mime;
  return 'data:$safeMime;base64,${base64Encode(imageBytes)}';
}

/// Document chunk for `POST /v1/ocr` (image bytes as a data URL).
///
/// Wire shape matches Mistral ImageURLChunk: flat string `image_url` with a
/// `data:image/…;base64,…` value.
///
/// Note: `mistralai_dart` 8.1.0's [OcrRequest.fromBase64] emits `type: base64`,
/// which the API rejects with HTTP 422 — use this shape instead.
Map<String, Object?> buildMistralOcrDocument({
  required Uint8List imageBytes,
  required String mime,
}) {
  return {
    'type': 'image_url',
    'image_url': mistralImageDataUrl(imageBytes, mime),
  };
}

/// Full JSON-encodable body for `POST /v1/ocr`.
Map<String, Object?> buildMistralOcrRequestBody({
  required String model,
  required Uint8List imageBytes,
  required String mime,
}) {
  return {
    'model': model,
    'document': buildMistralOcrDocument(imageBytes: imageBytes, mime: mime),
  };
}
