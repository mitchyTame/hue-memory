import 'dart:convert';
import 'dart:typed_data';

import 'image_mime.dart';

/// Normalize MIME for Mistral data URLs (`image/jpg` → `image/jpeg`).
String resolveOcrMime(
  Uint8List bytes, {
  String? imageMimeType,
  String? extensionHint,
}) {
  // Magic bytes win — never label JPEG bytes as PNG (or vice versa).
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
/// Wire shape matches mistralai ImageURLChunk: flat string `image_url` with a
/// `data:image/…;base64,…` value (nested `{url:…}` is also accepted by the
/// API union; we use the flat form documented in the current SDK).
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

/// Pull Mistral's human `message` out of an error JSON body.
///
/// Bodies look like:
/// `{"object":"error","message":"…","type":"invalid_request_error",…}`
String? mistralApiErrorMessage(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return null;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) {
      final message = decoded['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
      final error = decoded['error'];
      if (error is Map) {
        final nested = error['message'];
        if (nested is String && nested.trim().isNotEmpty) {
          return nested.trim();
        }
      }
      if (error is String && error.trim().isNotEmpty) {
        return error.trim();
      }
    }
  } catch (_) {
    // Not JSON — fall through.
  }
  return null;
}

/// User-facing HTTP failure line (prefers API `message`, never raw object dump).
String mistralHttpUserMessage(int status, String body) {
  final apiMessage = mistralApiErrorMessage(body);
  switch (status) {
    case 401:
    case 403:
      return 'Mistral rejected the API key (HTTP $status)';
    case 404:
      return 'Mistral OCR endpoint not found (HTTP 404)';
    case 429:
      return 'Mistral rate limit — try again shortly (HTTP 429)';
    case >= 500:
      return apiMessage == null
          ? 'Mistral server error (HTTP $status)'
          : 'Mistral server error (HTTP $status): $apiMessage';
    default:
      if (apiMessage != null) {
        return 'Mistral OCR failed (HTTP $status): $apiMessage';
      }
      final snippet =
          body.length > 120 ? '${body.substring(0, 120)}…' : body;
      return 'Mistral OCR failed (HTTP $status)'
          '${snippet.isEmpty ? '' : ': $snippet'}';
  }
}
