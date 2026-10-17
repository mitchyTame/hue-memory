import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/writers/markdown_writer.dart';

void main() {
  const writer = MarkdownWriter();

  test('writes YAML frontmatter and note sections', () {
    final md = writer.write(
      MarkdownNoteDraft(
        frontmatter: NoteFrontmatter(
          type: 'permanent',
          symbol: 'permanent',
          glyph: '◇',
          pageId: '20261016-p7k2',
          capturedAt: DateTime.utc(2026, 10, 16, 12, 5),
          sourceImage: 'captures/raw/20261016-p7k2.jpg',
          ocrConfidence: 0.78,
          links: const ['[[fleeting/prior-note]]'],
        ),
        noteBody: 'Attention is a muscle.',
      ),
    );

    expect(md, contains('---\n'));
    expect(md, contains('type: permanent'));
    expect(md, contains('glyph: ◇'));
    expect(md, contains('page_id: 20261016-p7k2'));
    expect(md, contains('captured_at: 2026-10-16T12:05:00.000Z'));
    expect(md, contains('ocr_confidence: 0.78'));
    expect(md, contains('links: ["[[fleeting/prior-note]]"]'));
    expect(md, isNot(contains('meaning:')));
    expect(md, contains('![[captures/raw/20261016-p7k2.jpg]]'));
    expect(md, contains('## Note'));
    expect(md, contains('Attention is a muscle.'));
    // Personal v2: one body only — never duplicate "## OCR draft".
    expect(md, isNot(contains('## OCR draft')));
    expect(md.trimRight(), endsWith('Attention is a muscle.'));
  });

  test('writes nested tags frontmatter when present', () {
    final md = writer.write(
      MarkdownNoteDraft(
        frontmatter: NoteFrontmatter(
          type: 'fleeting',
          symbol: 'fleeting',
          glyph: '∼',
          pageId: '20261016-tags',
          capturedAt: DateTime.utc(2026, 10, 16),
          sourceImage: 'captures/raw/20261016-tags.jpg',
          tags: const ['psychology/memory', 'psychology/memory/encoding'],
        ),
        noteBody: 'Tagged thought',
      ),
    );
    expect(
      md,
      contains('tags: ["psychology/memory", "psychology/memory/encoding"]'),
    );
  });

  test('empty links serialize as []', () {
    final md = writer.write(
      MarkdownNoteDraft(
        frontmatter: NoteFrontmatter(
          type: 'fleeting',
          symbol: 'fleeting',
          glyph: '∼',
          pageId: '20261016-aaaa',
          capturedAt: DateTime.utc(2026, 10, 16),
          sourceImage: 'captures/raw/20261016-aaaa.jpg',
        ),
        noteBody: 'Quick thought',
      ),
    );
    expect(md, contains('links: []'));
    expect(md, isNot(contains('## OCR draft')));
  });
}
