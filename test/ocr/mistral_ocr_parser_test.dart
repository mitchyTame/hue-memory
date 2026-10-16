import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/ocr/mistral_ocr_parser.dart';
import 'package:mistralai_dart/mistralai_dart.dart';

void main() {
  const parser = MistralOcrParser();

  test('parses OcrResponse markdown into regions', () {
    final result = parser.parseResponse(
      const OcrResponse(
        model: 'mistral-ocr-latest',
        pages: [
          OcrPage(
            index: 0,
            markdown: '◇ Permanent idea\n\nSecond paragraph about attention.',
          ),
        ],
      ),
    );

    expect(result.detectedGlyph, '◇');
    expect(result.regions, hasLength(2));
    expect(result.regions.first.text, contains('Permanent'));
    expect(result.pageGenre, 'text');
    expect(result.rawJson['provider'], 'mistral');
  });

  test('parses pages markdown into regions (map fixture)', () {
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
