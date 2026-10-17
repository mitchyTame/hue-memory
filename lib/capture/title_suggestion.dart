/// OCR / vision → optional title **hint** only (never auto-fills the filename).
///
/// Mitch types the real title. Suggestions must not carry image markers,
/// region tags, or other markdown scrap into the confirm field.
abstract final class TitleSuggestion {
  /// First markdown heading from OCR, sanitized — or empty when none / junk.
  static String fromOcrMarkdown(String markdown) {
    final cleaned = stripImageArtifacts(markdown);
    if (cleaned.trim().isEmpty) return '';

    final heading = RegExp(
      r'^#{1,6}\s+(.+?)\s*$',
      multiLine: true,
    ).firstMatch(cleaned);
    if (heading != null) {
      return sanitize(heading.group(1)!);
    }
    // No heading → no suggestion (don't invent from body / image scraps).
    return '';
  }

  /// Clean a candidate hint (diagram first node, OCR heading, etc.).
  static String sanitize(String raw) {
    var s = stripImageArtifacts(raw);
    s = s.replaceAll(RegExp(r'[*_`~]+'), '');
    s = s.replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1');
    s = s.replaceAll(RegExp(r'[\[\]{}()<>|\\]+'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Drop leftovers that are only media / region noise.
    if (s.isEmpty) return '';
    if (RegExp(r'^(image|img|media|region\d*|r\d+)$', caseSensitive: false)
        .hasMatch(s)) {
      return '';
    }
    if (s.length <= 48) return s;
    return '${s.substring(0, 45).trimRight()}…';
  }

  /// Remove image / embed markers that OCR and models often emit.
  ///
  /// Safe to run on a typed title as a belt-and-braces pass — leaves normal
  /// words alone.
  static String stripImageArtifacts(String raw) {
    var s = raw;
    // Obsidian embeds: ![[captures/raw/…]]
    s = s.replaceAll(RegExp(r'!\[\[[^\]]*\]\]'), ' ');
    // Markdown images: ![alt](url) and broken variants ![…]
    s = s.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ');
    s = s.replaceAll(RegExp(r'!\[[^\]]*\]'), ' ');
    // HTML img
    s = s.replaceAll(RegExp(r'<img\b[^>]*>', caseSensitive: false), ' ');
    // Mistral / vision scraps: ["image], ["image}], !["image}], …
    s = s.replaceAll(
      RegExp(r'''!?\[["']?image[^\]\n]*\]''', caseSensitive: false),
      ' ',
    );
    s = s.replaceAll(
      RegExp(r'''\[["']?image["']?\}+''', caseSensitive: false),
      ' ',
    );
    s = s.replaceAll(
      RegExp(r'''["']image["']\s*\}?''', caseSensitive: false),
      ' ',
    );
    s = s.replaceAll(RegExp(r'\bmediaimage\b', caseSensitive: false), ' ');
    s = s.replaceAll(
      RegExp(r'\bimg-\d+\.(jpe?g|png|gif|webp)\b', caseSensitive: false),
      ' ',
    );
    // Region tags that must never ride into a filename.
    s = s.replaceAll(RegExp(r'\bregion\d+\b', caseSensitive: false), ' ');
    // Bare OCR region ids (r1, r12) — not the letter R alone.
    s = s.replaceAll(RegExp(r'(^|[^\w])r\d+\b'), r'$1');
    return s;
  }
}
