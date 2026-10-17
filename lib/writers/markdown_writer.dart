/// Frontmatter + body for a text note (inbox / fleeting / literature / permanent).
///
/// No `meaning.json` path — vault holds `.md` / `.canvas` / images only.
class NoteFrontmatter {
  const NoteFrontmatter({
    required this.type,
    required this.symbol,
    required this.glyph,
    required this.pageId,
    required this.capturedAt,
    required this.sourceImage,
    this.ocrConfidence,
    this.status = 'confirmed',
    this.links = const [],
    this.tags = const [],
    this.threadTick = false,
  });

  final String type;
  final String symbol;
  final String glyph;
  final String pageId;
  final DateTime capturedAt;
  final String sourceImage;
  final double? ocrConfidence;
  final String status;
  final List<String> links;

  /// Nested Obsidian tags without leading `#` (e.g. `psychology/memory`).
  final List<String> tags;
  final bool threadTick;
}

class MarkdownNoteDraft {
  const MarkdownNoteDraft({
    required this.frontmatter,
    required this.noteBody,
    @Deprecated('Personal v2: single ## Note body — OCR draft section removed')
    this.ocrDraft = '',
  });

  final NoteFrontmatter frontmatter;
  final String noteBody;

  /// Ignored — kept for API compat. Vault notes are one ## Note only.
  @Deprecated('Personal v2: single ## Note body')
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
    final tagsYaml = fm.tags.isEmpty
        ? '[]'
        : '[${fm.tags.map(_yamlString).join(', ')}]';

    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('type: ${fm.type}')
      ..writeln('symbol: ${fm.symbol}')
      ..writeln('glyph: ${fm.glyph}')
      ..writeln('page_id: ${fm.pageId}')
      ..writeln('captured_at: ${fm.capturedAt.toUtc().toIso8601String()}')
      ..writeln('source_image: ${fm.sourceImage}');
    if (fm.ocrConfidence != null) {
      buffer.writeln(
        'ocr_confidence: ${fm.ocrConfidence!.toStringAsFixed(2)}',
      );
    }
    if (fm.threadTick) {
      buffer.writeln('thread_tick: true');
    }
    buffer
      ..writeln('status: ${fm.status}')
      ..writeln('links: $linksYaml');
    if (fm.tags.isNotEmpty) {
      buffer.writeln('tags: $tagsYaml');
    }
    buffer
      ..writeln('---')
      ..writeln();
    if (fm.sourceImage.trim().isNotEmpty) {
      buffer
        ..writeln('![[${fm.sourceImage}]]')
        ..writeln();
    }
    // One body only — never a duplicate "## OCR draft" section.
    buffer
      ..writeln('## Note')
      ..writeln()
      ..writeln(draft.noteBody.trim())
      ..writeln();
    return buffer.toString();
  }

  static String _yamlString(String value) {
    final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }
}
