import 'package:mistralai_dart/mistralai_dart.dart';

import 'ocr_client.dart';

/// Maps Mistral OCR output into [MeaningResult].
///
/// Symbol detection is a light heuristic on markdown text (corner glyph OCR
/// comes later). Unknown → inbox glyph `○`.
class MistralOcrParser {
  const MistralOcrParser();

  /// Preferred path — typed [OcrResponse] from `mistralai_dart`.
  MeaningResult parseResponse(OcrResponse response) {
    final markdownChunks = response.pages
        .map((p) => p.markdown.trim())
        .where((md) => md.isNotEmpty)
        .toList();
    return _fromMarkdownChunks(
      markdownChunks,
      model: response.model,
    );
  }

  /// Legacy / fixture path — raw JSON map (same shape as the OCR API body).
  MeaningResult parse(Map<String, dynamic> json) {
    final pages = json['pages'];
    final markdownChunks = <String>[];
    if (pages is List) {
      for (final page in pages) {
        if (page is Map && page['markdown'] is String) {
          final md = (page['markdown'] as String).trim();
          if (md.isNotEmpty) markdownChunks.add(md);
        }
      }
    }
    return _fromMarkdownChunks(
      markdownChunks,
      model: json['model']?.toString(),
    );
  }

  MeaningResult _fromMarkdownChunks(
    List<String> markdownChunks, {
    String? model,
  }) {
    final full = markdownChunks.join('\n\n');
    final regions = _regionsFromMarkdown(full);
    final glyph = detectGlyph(full);
    final genre = glyph == '·'
        ? 'task_list'
        : glyph == '△'
            ? 'visual'
            : 'text';

    return MeaningResult(
      detectedGlyph: glyph,
      regions: regions,
      pageGenre: genre,
      rawJson: {
        'provider': 'mistral',
        'model': model,
        'pages': markdownChunks.length,
      },
    );
  }

  /// Prefer circled ZK glyphs appearing in the OCR text.
  String detectGlyph(String markdown) {
    const candidates = ['◇', '△', '≡', '∼', '○', '·', '•'];
    for (final g in candidates) {
      if (markdown.contains(g)) {
        return g == '•' ? '·' : g;
      }
    }
    // Letter aliases (optional)
    final upper = markdown.toUpperCase();
    if (RegExp(r'\bP\b').hasMatch(upper)) return '◇';
    if (RegExp(r'\bV\b').hasMatch(upper)) return '△';
    if (RegExp(r'\bL\b').hasMatch(upper)) return '≡';
    if (RegExp(r'\bF\b').hasMatch(upper)) return '∼';
    if (RegExp(r'\bI\b').hasMatch(upper)) return '○';
    return '○'; // inbox fallback when uncertain
  }

  List<OcrRegion> _regionsFromMarkdown(String markdown) {
    if (markdown.trim().isEmpty) {
      return const [
        OcrRegion(
          id: 'r1',
          text: '',
          confidence: 0.5,
          bbox: [0.1, 0.1, 0.8, 0.2],
        ),
      ];
    }

    final blocks = markdown
        .split(RegExp(r'\n\s*\n'))
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty)
        .toList();

    if (blocks.isEmpty) {
      return [
        OcrRegion(
          id: 'r1',
          text: markdown.trim(),
          confidence: 0.8,
          bbox: const [0.1, 0.15, 0.8, 0.2],
        ),
      ];
    }

    final regions = <OcrRegion>[];
    final n = blocks.length;
    for (var i = 0; i < n; i++) {
      final top = 0.12 + (i / n) * 0.7;
      final height = (0.7 / n).clamp(0.06, 0.25);
      regions.add(
        OcrRegion(
          id: 'r${i + 1}',
          text: blocks[i],
          confidence: 0.85,
          bbox: [0.1, top, 0.8, height],
        ),
      );
    }
    return regions;
  }
}
