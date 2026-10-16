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
    this.threadTick = false,
    this.rawJson = const {},
  });

  final String detectedGlyph;
  final List<OcrRegion> regions;
  final String pageGenre;

  /// Meta-zone one-stroke `›` — continue previous capture (confirm pre-check).
  final bool threadTick;

  final Map<String, Object?> rawJson;
}

/// Cloud / on-device OCR boundary. MVP: Mistral cloud + consent.
///
/// Live: [MistralOcrClient] via [ConfigurableOcrClient] when key + consent.
/// TODO(ocr): offline capture queue + retry when network returns.
abstract interface class OcrClient {
  Future<MeaningResult> extractMeaning(Uint8List imageBytes);
}
