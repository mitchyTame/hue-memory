import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/gemini/capture_coordinator.dart';
import 'package:hue_memory/gemini/gemini_client.dart';
import 'package:hue_memory/gemini/gemini_settings.dart';
import 'package:hue_memory/ocr/mock_ocr_client.dart';

void main() {
  group('CaptureCoordinator', () {
    test('forced visual never OCR-first (offline stub diagram)', () async {
      final ocr = MockOcrClient();
      final coord = CaptureCoordinator(
        geminiSettings: MemoryGeminiSettingsStore(),
        ocr: ocr,
      );
      final result = await coord.run(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        forcedSymbolId: 'visual',
      );
      expect(result.isDiagram, isTrue);
      expect(result.meaning.detectedGlyph, '△');
      expect(ocr.callCount, 0);
    });

    test('without force and without Gemini → OCR text path', () async {
      final ocr = MockOcrClient(glyph: '∼');
      final coord = CaptureCoordinator(
        geminiSettings: MemoryGeminiSettingsStore(),
        ocr: ocr,
      );
      final result = await coord.run(
        imageBytes: Uint8List.fromList([9]),
      );
      expect(result.isTextPage, isTrue);
      expect(ocr.callCount, 1);
    });

    test('non-visual forced symbol still classifies via OCR when offline',
        () async {
      final ocr = MockOcrClient(glyph: '∼');
      final coord = CaptureCoordinator(
        geminiSettings: MemoryGeminiSettingsStore(),
        ocr: ocr,
      );
      final result = await coord.run(
        imageBytes: Uint8List.fromList([4]),
        forcedSymbolId: 'fleeting',
      );
      expect(result.isTextPage, isTrue);
      expect(ocr.callCount, 1);
    });
  });

  test('CaptureClass.wireName stable for routing debug', () {
    expect(CaptureClass.diagram.wireName, 'diagram');
    expect(CaptureClass.photoOnly.wireName, 'photo_only');
    expect(CaptureClass.textPage.wireName, 'text_page');
  });
}
