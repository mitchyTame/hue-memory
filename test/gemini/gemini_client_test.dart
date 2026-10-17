import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/gemini/gemini_client.dart';
import 'package:hue_memory/gemini/gemini_settings.dart';

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

  test('empty key verify fails without network', () async {
    final client = GeminiClient(apiKey: '');
    final result = await client.verifyConnection();
    expect(result.ok, isFalse);
    expect(result.message.toLowerCase(), contains('empty'));
  });

  test('defaults stay on flash-lite for both roles', () {
    final client = GeminiClient(apiKey: 'AIza-test');
    expect(client.model, GeminiSettings.defaultModel);
    expect(client.classifyModel, GeminiSettings.defaultModel);
    expect(client.diagramModel, GeminiSettings.defaultModel);
    expect(client.model, 'gemini-3.5-flash-lite');
  });
}
