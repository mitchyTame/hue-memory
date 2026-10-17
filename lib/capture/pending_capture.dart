import 'dart:typed_data';

import '../ocr/ocr_client.dart';
import '../writers/link_writer.dart';
import 'region_feedback.dart';

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
    this.draftTitleSuggestion = '',
    this.regionFeedback = CaptureRegionFeedback.none,
  })  : // Manual title required before save — never auto-commit a default.
        title = title ?? '',
        noteBody = noteBody ?? _joinedRegions(meaning),
        symbolId = symbolId ?? '',
        links = List<LinkPick>.from(links ?? const []);

  final String pageId;
  final Uint8List imageBytes;
  final DateTime capturedAt;
  final String imageExtension;
  final MeaningResult meaning;

  /// Optional OCR/vision draft shown as a hint — not the save name.
  final String draftTitleSuggestion;

  /// OCR region for confirm overlay only (never written to vault image).
  final CaptureRegionFeedback regionFeedback;

  String title;
  String noteBody;

  /// Confirmed pack symbol id (empty until router assigns from glyph).
  String symbolId;
  List<LinkPick> links;

  String get rawImagePath =>
      'captures/raw/$pageId.$imageExtension';

  String get ocrDraft => _joinedRegions(meaning);

  List<String> get taskLines => meaning.regions
      .map((r) => r.text.trim())
      .where((t) => t.isNotEmpty)
      .map(_stripBulletPrefix)
      .toList(growable: false);

  static String _joinedRegions(MeaningResult meaning) {
    // Text / handwriting: prefer full OCR markdown when present.
    if (meaning.pageGenre != 'visual') {
      final full = meaning.rawJson['full_markdown'];
      if (full is String && full.trim().isNotEmpty) {
        return full.trim();
      }
    }
    // Visual / mindmap: short label lines only — never a page prose dump.
    final sep = meaning.pageGenre == 'visual' ? '\n' : '\n\n';
    return meaning.regions
        .map((r) => r.text.trim())
        .where((t) => t.isNotEmpty)
        .take(meaning.pageGenre == 'visual' ? 12 : 200)
        .join(sep);
  }

  static String _stripBulletPrefix(String line) {
    return line.replaceFirst(RegExp(r'^[·•\-\*○]\s*'), '');
  }
}
