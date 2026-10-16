import '../writers/link_writer.dart';

/// One-stroke `›` thread — continues the previous page in this session.
///
/// Paper habit: draw `›` in the meta zone. Confirm pre-checks the last
/// capture as a link; the Link picker always wins / merges.
abstract final class ThreadTick {
  static const mark = '›';
  static const asciiFallback = '>';

  /// True when meaning / meta text includes a thread chevron.
  static bool detectedIn(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return false;
    return s.contains(mark) || s.contains(asciiFallback);
  }

  /// Strip thread marks so symbol routing sees only the type glyph.
  static String stripFromGlyph(String raw) {
    return raw
        .replaceAll(mark, '')
        .replaceAll(asciiFallback, '')
        .replaceAll(' ', '')
        .trim();
  }

  /// Prepend [previous] into [existing] unless already linked.
  static List<LinkPick> mergePrevious({
    required LinkPick? previous,
    List<LinkPick> existing = const [],
  }) {
    if (previous == null) return List<LinkPick>.from(existing);
    final prevPath = _norm(previous.targetPath);
    if (existing.any((e) => _norm(e.targetPath) == prevPath)) {
      return List<LinkPick>.from(existing);
    }
    return [previous, ...existing];
  }

  static String _norm(String path) {
    var t = path.trim();
    if (t.toLowerCase().endsWith('.md')) {
      t = t.substring(0, t.length - 3);
    }
    return t;
  }
}
