/// Light OCR → acceptable markdown. Does not invent content or sections.
///
/// Normalizes checkbox glyphs / forced wraps; keeps the writer's structure.
/// Section labels may gain `**Label:**` emphasis; prose and bullets stay as-is.
class DailyNoteMarkdown {
  const DailyNoteMarkdown._();

  static final RegExp _checkboxLine = RegExp(
    r'^(\s*)(?:[-*+]\s+)?\[([ xX])\]\s*(.*)$',
  );
  static final RegExp _ocrBoxLine = RegExp(
    r'^(\s*)(?:☐|☑|☒|□|■|\[\s*\]|\[x\]|\[X\])\s*(.*)$',
  );
  static final RegExp _bulletLine = RegExp(
    r'^(\s*)([-*+·•])\s+(.*)$',
  );
  static final RegExp _sectionLabel = RegExp(
    r'^([A-Za-z][\w\s/&-]{0,48}):\s*$',
  );
  static final RegExp _dateLine = RegExp(
    r"^(\d{1,2}\s+[A-Za-z]{3,9}\s+'?\d{2,4}|\d{4}-\d{2}-\d{2})\s*$",
  );
  static final RegExp _forcedCheckboxBullet = RegExp(
    r'^(\s*)[-*+]\s+\[[ xX]\]\s+([-*+·•]\s+.*)$',
  );

  /// Convert [source] (OCR markdown or confirm body) into structured markdown.
  static String interpret(String source) {
    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (normalized.trim().isEmpty) return '';

    final out = <String>[];
    for (final raw in normalized.split('\n')) {
      out.add(interpretLine(raw));
    }
    return _collapseBlankLines(out).join('\n').trimRight();
  }

  /// Interpret a single line (also used when callers still pass task lists).
  static String interpretLine(String raw) {
    final line = raw.replaceAll('\t', '  ');
    if (line.trim().isEmpty) return '';

    // Already a heading or bold section — keep.
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('#')) return line.trimRight();
    if (RegExp(r'^\*\*[^*].*\*\*:?\s*$').hasMatch(trimmed)) {
      return trimmed;
    }

    // Forced checkbox wrapping a nested bullet: `- [ ] - item` → `- item`
    final forcedBullet = _forcedCheckboxBullet.firstMatch(line);
    if (forcedBullet != null) {
      final indent = forcedBullet.group(1) ?? '';
      final rest = forcedBullet.group(2)!.trimLeft();
      return interpretLine('$indent$rest');
    }

    // Standard markdown checkbox.
    final cb = _checkboxLine.firstMatch(line);
    if (cb != null) {
      final indent = cb.group(1) ?? '';
      final checked = cb.group(2)!.toLowerCase() == 'x';
      final content = (cb.group(3) ?? '').trimRight();
      return _fromCheckboxContent(indent, checked, content);
    }

    // OCR box glyphs / bare [ ] prefixes.
    final box = _ocrBoxLine.firstMatch(line);
    if (box != null) {
      final indent = box.group(1) ?? '';
      final mark = line.trimLeft();
      final checked = mark.startsWith('☑') ||
          mark.startsWith('☒') ||
          mark.startsWith('■') ||
          mark.toLowerCase().startsWith('[x]');
      final content = (box.group(2) ?? '').trimRight();
      return _fromCheckboxContent(indent, checked, content);
    }

    // Nested / plain bullets (not checkboxes).
    final bullet = _bulletLine.firstMatch(line);
    if (bullet != null) {
      final indent = bullet.group(1) ?? '';
      final content = (bullet.group(3) ?? '').trimRight();
      if (_isSectionLabel(content)) {
        return _formatSection(content);
      }
      return '$indent- $content';
    }

    if (_isSectionLabel(trimmed)) {
      return _formatSection(trimmed);
    }

    return line.trimRight();
  }

  static String _fromCheckboxContent(
    String indent,
    bool checked,
    String content,
  ) {
    final text = content.trim();
    if (text.isEmpty) {
      return checked ? '$indent- [x]' : '$indent- [ ]';
    }

    // Nested bullet after a mistaken checkbox wrap.
    final nested = _bulletLine.firstMatch(text);
    if (nested != null) {
      final inner = (nested.group(3) ?? '').trimRight();
      return '$indent- $inner';
    }

    if (_isSectionLabel(text)) {
      return _formatSection(text);
    }

    if (_looksLikeProseOrMeta(text)) {
      return text;
    }

    final mark = checked ? 'x' : ' ';
    return '$indent- [$mark] $text';
  }

  /// Section labels, dates, lone glyphs, and sentence prose are not tasks.
  static bool _looksLikeProseOrMeta(String text) {
    if (_isSectionLabel(text)) return true;
    if (_dateLine.hasMatch(text)) return true;
    if (RegExp(r'^[\u2600-\u26FF\u2700-\u27BF☉○·•△◇∼≡]+$').hasMatch(text)) {
      return true;
    }
    // Multi-sentence / long journal prose.
    if (text.length > 72) return true;
    if (text.contains('. ') || text.endsWith('.')) {
      if (text.split(RegExp(r'\s+')).length >= 6) return true;
    }
    return false;
  }

  static bool _isSectionLabel(String text) {
    final t = text.trim();
    if (!_sectionLabel.hasMatch(t)) return false;
    // Avoid treating URLs or times as sections.
    if (t.contains('://')) return false;
    return true;
  }

  static String _formatSection(String label) {
    final t = label.trim();
    if (t.startsWith('**') && t.endsWith('**')) return t;
    final core = t.endsWith(':') ? t.substring(0, t.length - 1).trim() : t;
    return '**$core:**';
  }

  static List<String> _collapseBlankLines(List<String> lines) {
    final out = <String>[];
    var blankRun = 0;
    for (final line in lines) {
      if (line.isEmpty) {
        blankRun++;
        if (blankRun <= 1) out.add('');
        continue;
      }
      blankRun = 0;
      out.add(line);
    }
    while (out.isNotEmpty && out.last.isEmpty) {
      out.removeLast();
    }
    return out;
  }
}
