import 'dart:typed_data';

/// One OCR / meaning region from a page photo.
class OcrRegion {
  const OcrRegion({
    required this.id,
    required this.text,
    required this.confidence,
    this.bbox,
  });

  final String id;
  final String text;
  final double confidence;

  /// Optional [left, top, width, height] in image coordinates.
  final List<double>? bbox;
}

/// Meaning extract for a capture (symbol + regions + optional graph).
class MeaningResult {
  const MeaningResult({
    required this.detectedGlyph,
    required this.regions,
    this.pageGenre = 'text',
    this.rawJson = const {},
  });

  final String detectedGlyph;
  final List<OcrRegion> regions;
  final String pageGenre;
  final Map<String, Object?> rawJson;
}

/// Cloud / on-device OCR boundary. MVP: Mistral cloud + consent.
///
/// TODO(ocr): Implement [MistralOcrClient] with multipart upload + queue.
abstract interface class OcrClient {
  Future<MeaningResult> extractMeaning(Uint8List imageBytes);
}
