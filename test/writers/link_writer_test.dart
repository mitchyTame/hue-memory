import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/writers/link_writer.dart';
import 'package:hue_memory/writers/markdown_writer.dart';

void main() {
  const links = LinkWriter();
  const markdown = MarkdownWriter();

  test('link picker writes wikilinks without .md suffix', () {
    expect(
      links.wikilink(const LinkPick(targetPath: 'permanent/attention.md')),
      '[[permanent/attention]]',
    );
    expect(
      links.wikilink(
        const LinkPick(
          targetPath: 'fleeting/wave-1',
          displayTitle: 'Earlier wave',
        ),
      ),
      '[[fleeting/wave-1|Earlier wave]]',
    );
  });

  test('frontmatter links land in markdown writer output', () {
    final picks = [
      const LinkPick(targetPath: 'permanent/attention.md'),
      const LinkPick(targetPath: 'literature/book-notes'),
    ];
    final fmLinks = links.frontmatterLinks(picks);
    final md = markdown.write(
      MarkdownNoteDraft(
        frontmatter: NoteFrontmatter(
          type: 'fleeting',
          symbol: 'fleeting',
          glyph: '∼',
          pageId: '20261016-link',
          capturedAt: DateTime.utc(2026, 10, 16),
          sourceImage: 'captures/raw/20261016-link.jpg',
          links: fmLinks,
        ),
        noteBody: 'Linked from confirm picker',
      ),
    );

    expect(md, contains('[[permanent/attention]]'));
    expect(md, contains('[[literature/book-notes]]'));
    expect(links.linkedSection(picks), contains('## Linked'));
    expect(links.linkedSection(picks), contains('- [[permanent/attention]]'));
  });
}
