import 'dart:typed_data';

import 'ocr_client.dart';

/// Deterministic OCR stub for tests and offline UI shell.
class MockOcrClient implements OcrClient {
  MockOcrClient({
    this.glyph = '∼',
    List<OcrRegion>? regions,
    this.pageGenre = 'text',
  }) : regions = regions ?? defaultFleetingRegions;

  final String glyph;
  final List<OcrRegion> regions;
  final String pageGenre;

  int callCount = 0;

  static const defaultFleetingRegions = <OcrRegion>[
    OcrRegion(
      id: 'r1',
      text: 'Attention is a muscle',
      confidence: 0.91,
      bbox: [0.12, 0.18, 0.70, 0.08],
    ),
    OcrRegion(
      id: 'r2',
      text: 'Practice on paper first, then confirm meaning.',
      confidence: 0.84,
      bbox: [0.12, 0.32, 0.76, 0.10],
    ),
  ];

  static const defaultTaskRegions = <OcrRegion>[
    OcrRegion(
      id: 't1',
      text: 'Buy ink cartridges',
      confidence: 0.93,
      bbox: [0.14, 0.22, 0.62, 0.07],
    ),
    OcrRegion(
      id: 't2',
      text: 'Review fleeting notes',
      confidence: 0.88,
      bbox: [0.14, 0.34, 0.58, 0.07],
    ),
  ];

  static const defaultVisualRegions = <OcrRegion>[
    OcrRegion(
      id: 'n1',
      text: 'Central idea',
      confidence: 0.86,
      bbox: [0.35, 0.28, 0.30, 0.10],
    ),
    OcrRegion(
      id: 'n2',
      text: 'Branch',
      confidence: 0.80,
      bbox: [0.55, 0.48, 0.28, 0.09],
    ),
  ];

  /// Convenience factory for a glyph-aware demo stub.
  factory MockOcrClient.forGlyph(String glyph) {
    switch (glyph.trim()) {
      case '·':
      case '•':
        return MockOcrClient(
          glyph: '·',
          regions: defaultTaskRegions,
          pageGenre: 'task_list',
        );
      case '△':
      case 'V':
        return MockOcrClient(
          glyph: '△',
          regions: defaultVisualRegions,
          pageGenre: 'visual',
        );
      default:
        return MockOcrClient(glyph: glyph);
    }
  }

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
