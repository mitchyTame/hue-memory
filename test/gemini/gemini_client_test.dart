import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/gemini/gemini_client.dart';

void main() {
  test('CaptureClass.parse maps aliases', () {
    expect(CaptureClass.parse('text_page'), CaptureClass.textPage);
    expect(CaptureClass.parse('diagram'), CaptureClass.diagram);
    expect(CaptureClass.parse('visual_map'), CaptureClass.diagram);
    expect(CaptureClass.parse('photo_only'), CaptureClass.photoOnly);
    expect(CaptureClass.parse('junk'), CaptureClass.textPage);
  });

  test('stripFencesAndSliceJson removes markdown fences', () {
    const raw = '```json\n{"nodes":[],"edges":[]}\n```';
    final sliced = GeminiClient.stripFencesAndSliceJson(raw);
    expect(sliced.startsWith('{'), isTrue);
    expect(sliced.contains('```'), isFalse);
  });
}
