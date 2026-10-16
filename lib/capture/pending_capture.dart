import 'dart:typed_data';

import '../ocr/ocr_client.dart';
import '../writers/link_writer.dart';

/// In-flight capture waiting on the confirm UI.
class PendingCapture {
  PendingCapture({
    required this.pageId,
    required this.imageBytes,
    required this.capturedAt,
    required this.meaning,
    this.imageExtension = 'png',
    String? title,
    String? noteBody,
    String? symbolId,
    List<LinkPick>? links,
  })  : title = title ?? _defaultTitle(meaning),
        noteBody = noteBody ?? _joinedRegions(meaning),
        symbolId = symbolId ?? '',
        links = List<LinkPick>.from(links ?? const []);

  final String pageId;
  final Uint8List imageBytes;
  final DateTime capturedAt;
  final String imageExtension;
  final MeaningResult meaning;

  String title;
  String noteBody;

  /// Confirmed pack symbol id (empty until router assigns from glyph).
  String symbolId;
  List<LinkPick> links;

  String get rawImagePath =>
      'captures/raw/$pageId.$imageExtension';

  String get meaningPath => 'captures/raw/$pageId.meaning.json';

  String get ocrDraft => _joinedRegions(meaning);

  List<String> get taskLines => meaning.regions
      .map((r) => r.text.trim())
      .where((t) => t.isNotEmpty)
      .map(_stripBulletPrefix)
      .toList(growable: false);

  static String _defaultTitle(MeaningResult meaning) {
    final first = meaning.regions
        .map((r) => r.text.trim())
        .firstWhere((t) => t.isNotEmpty, orElse: () => 'Untitled page');
    if (first.length <= 48) return first;
    return '${first.substring(0, 45)}…';
  }

  static String _joinedRegions(MeaningResult meaning) {
    // Visual / mindmap: short label lines only — never a page prose dump.
    final sep = meaning.pageGenre == 'visual' ? '\n' : '\n\n';
    return meaning.regions
        .map((r) => r.text.trim())
        .where((t) => t.isNotEmpty)
        .take(meaning.pageGenre == 'visual' ? 12 : 100)
        .join(sep);
  }

  static String _stripBulletPrefix(String line) {
    return line.replaceFirst(RegExp(r'^[·•\-\*○]\s*'), '');
  }
}
