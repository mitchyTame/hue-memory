import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/ocr/mistral_ocr_parser.dart';

void main() {
  const parser = MistralOcrParser();

  test('parses pages markdown into regions', () {
    final result = parser.parse({
      'model': 'mistral-ocr-latest',
      'pages': [
        {
          'index': 0,
          'markdown': '◇ Permanent idea\n\nSecond paragraph about attention.',
        },
      ],
    });

    expect(result.detectedGlyph, '◇');
    expect(result.regions, hasLength(2));
    expect(result.regions.first.text, contains('Permanent'));
    expect(result.pageGenre, 'text');
    expect(result.rawJson['provider'], 'mistral');
  });

  test('detects daily-tasks glyph', () {
    expect(parser.detectGlyph('Tasks\n· Buy ink'), '·');
  });

  test('falls back to inbox when no glyph', () {
    expect(parser.detectGlyph('Just some notes'), '○');
  });
}
