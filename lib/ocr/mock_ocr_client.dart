import 'dart:typed_data';

import 'ocr_client.dart';

/// Deterministic OCR stub for tests and offline UI shell.
class MockOcrClient implements OcrClient {
  MockOcrClient({
    this.glyph = '∼',
    this.regions = const [
      OcrRegion(id: 'r1', text: 'Sample note line', confidence: 0.9),
    ],
    this.pageGenre = 'text',
  });

  final String glyph;
  final List<OcrRegion> regions;
  final String pageGenre;

  int callCount = 0;

  @override
  Future<MeaningResult> extractMeaning(Uint8List imageBytes) async {
    callCount++;
    return MeaningResult(
      detectedGlyph: glyph,
      regions: regions,
      pageGenre: pageGenre,
      rawJson: {
        'mock': true,
        'bytes': imageBytes.length,
      },
    );
  }
}
