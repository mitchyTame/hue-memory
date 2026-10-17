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
    expect(result.rawJson['full_markdown'], contains('Second paragraph'));
  });

  test('text path keeps full long paragraphs (no 64-char clipLabel)', () {
    final long = 'A' * 120;
    final result = parser.parseResponse(
      OcrResponse(
        model: 'mistral-ocr-latest',
        pages: [
          OcrPage(
            index: 0,
            markdown: '∼ Fleeting\n\n$long',
          ),
        ],
      ),
    );
    expect(result.pageGenre, 'text');
    expect(result.regions.last.text.length, greaterThanOrEqualTo(120));
    expect(result.regions.last.text, isNot(contains('…')));
    expect(result.rawJson['full_markdown'], contains(long));
  });

  test('letter L is not routed to literature', () {
    expect(parser.detectGlyph('See section L for notes'), '○');
    expect(parser.detectGlyph('≡ Literature note'), '≡');
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

  test('visual glyph builds hybrid mindmap regions, not prose dump', () {
    final result = parser.parseResponse(
      const OcrResponse(
        model: 'mistral-ocr-latest',
        pages: [
          OcrPage(
            index: 0,
            markdown: '△ Central idea\n\nBranch A\n\nBranch B\n\nBranch C',
          ),
        ],
      ),
    );

    expect(result.detectedGlyph, '△');
    expect(result.pageGenre, 'visual');
    expect(result.rawJson['hybrid_mindmap'], isTrue);
    expect(result.rawJson['mindmap'], isA<Map>());
    expect(result.regions, isNotEmpty);
    expect(result.regions.length, lessThanOrEqualTo(12));
    for (final r in result.regions) {
      expect(r.text.length, lessThanOrEqualTo(64));
    }
  });
}
