/// Frontmatter + body for a text note (inbox / fleeting / literature / permanent).
class NoteFrontmatter {
  const NoteFrontmatter({
    required this.type,
    required this.symbol,
    required this.glyph,
    required this.pageId,
    required this.capturedAt,
    required this.sourceImage,
    required this.meaning,
    this.ocrConfidence,
    this.status = 'confirmed',
    this.links = const [],
  });

  final String type;
  final String symbol;
  final String glyph;
  final String pageId;
  final DateTime capturedAt;
  final String sourceImage;
  final String meaning;
  final double? ocrConfidence;
  final String status;
  final List<String> links;
}

class MarkdownNoteDraft {
  const MarkdownNoteDraft({
    required this.frontmatter,
    required this.noteBody,
    this.ocrDraft = '',
  });

  final NoteFrontmatter frontmatter;
  final String noteBody;
  final String ocrDraft;
}

/// Pure-Dart Markdown + YAML frontmatter writer (no vault I/O).
class MarkdownWriter {
  const MarkdownWriter();

  String write(MarkdownNoteDraft draft) {
    final fm = draft.frontmatter;
    final linksYaml = fm.links.isEmpty
        ? '[]'
        : '[${fm.links.map(_yamlString).join(', ')}]';

    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('type: ${fm.type}')
      ..writeln('symbol: ${fm.symbol}')
      ..writeln('glyph: ${fm.glyph}')
      ..writeln('page_id: ${fm.pageId}')
      ..writeln('captured_at: ${fm.capturedAt.toUtc().toIso8601String()}')
      ..writeln('source_image: ${fm.sourceImage}')
      ..writeln('meaning: ${fm.meaning}');
    if (fm.ocrConfidence != null) {
      buffer.writeln(
        'ocr_confidence: ${fm.ocrConfidence!.toStringAsFixed(2)}',
      );
    }
    buffer
      ..writeln('status: ${fm.status}')
      ..writeln('links: $linksYaml')
      ..writeln('---')
      ..writeln();
    if (fm.sourceImage.trim().isNotEmpty) {
      buffer
        ..writeln('![[${fm.sourceImage}]]')
        ..writeln();
    }
    buffer
      ..writeln('## Note')
      ..writeln()
      ..writeln(draft.noteBody.trim())
      ..writeln();
    if (draft.ocrDraft.trim().isNotEmpty) {
      buffer
        ..writeln('## OCR draft')
        ..writeln()
        ..writeln(draft.ocrDraft.trim())
        ..writeln();
    }
    return buffer.toString();
  }

  static String _yamlString(String value) {
    final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }
}
