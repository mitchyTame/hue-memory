import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/capture/title_suggestion.dart';
import 'package:hue_memory/vault/commit_pipeline.dart';

void main() {
  group('TitleSuggestion.fromOcrMarkdown', () {
    test('uses first heading and strips image markers', () {
      const md = '''
# Attention is a muscle

!["image}](img-0.jpeg)

Some body text.
''';
      expect(TitleSuggestion.fromOcrMarkdown(md), 'Attention is a muscle');
    });

    test('empty when only image / media scraps', () {
      expect(
        TitleSuggestion.fromOcrMarkdown('!["image}](img-0.jpeg)\n\n![[x.png]]'),
        isEmpty,
      );
      expect(TitleSuggestion.fromOcrMarkdown('["image}]'), isEmpty);
    });

    test('empty when no heading (do not invent from body)', () {
      expect(
        TitleSuggestion.fromOcrMarkdown('Just a paragraph\n\nMore notes'),
        isEmpty,
      );
    });

    test('strips Obsidian embed and markdown image from heading line', () {
      expect(
        TitleSuggestion.fromOcrMarkdown(
          '# Hello ![[captures/raw/x.png]] world\n',
        ),
        'Hello world',
      );
    });
  });

  group('TitleSuggestion.sanitize', () {
    test('drops image-only candidates', () {
      expect(TitleSuggestion.sanitize('["image}]'), isEmpty);
      expect(TitleSuggestion.sanitize('image'), isEmpty);
      expect(TitleSuggestion.sanitize('![](foo.png)'), isEmpty);
    });

    test('keeps clean short labels', () {
      expect(TitleSuggestion.sanitize('Memory palace'), 'Memory palace');
    });
  });

  group('fileStemFromTitle', () {
    test('strips leaked image scrap without changing typed words', () {
      expect(
        CommitPipeline.fileStemFromTitle('Attention["image}]'),
        'Attention',
      );
      expect(
        CommitPipeline.fileStemFromTitle('My note ![[captures/raw/x.png]]'),
        'My note',
      );
      expect(
        CommitPipeline.fileStemFromTitle('Attention is a muscle'),
        'Attention is a muscle',
      );
    });
  });
}
