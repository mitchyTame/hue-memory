/// Output kind for a pack symbol — where vault writes go.
enum SymbolOutput {
  markdown,
  canvas,
  inbox,
  dailyNoteAppend,
}

/// One drawable ink glyph in the library (18 glyphs in full set).
class DrawGlyph {
  const DrawGlyph({
    required this.id,
    required this.unicode,
    required this.label,
  });

  final String id;
  final String unicode;
  final String label;
}

/// A configured symbol in an active pack.
class PackSymbol {
  const PackSymbol({
    required this.id,
    required this.draw,
    required this.glyphs,
    required this.output,
    this.folder,
    this.section,
    this.reviewGate,
  });

  final String id;
  final String draw;
  final List<String> glyphs;
  final SymbolOutput output;

  /// Vault-relative folder (null for daily-note-append).
  final String? folder;

  /// Heading for daily-note append (e.g. "## Tasks").
  final String? section;

  /// Optional gate such as `own_words` for permanents.
  final String? reviewGate;

  String get primaryGlyph => glyphs.isNotEmpty ? glyphs.first : '?';
}

/// Named symbol pack (e.g. zettelkasten-ink).
class SymbolPack {
  const SymbolPack({
    required this.id,
    required this.libraryRef,
    required this.symbols,
    this.label,
  });

  final String id;
  final String libraryRef;
  final List<PackSymbol> symbols;

  /// Human label for settings UI.
  final String? label;

  String get displayName => label ?? id;

  PackSymbol? byId(String id) {
    for (final s in symbols) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Resolve a detected glyph or letter alias to a pack symbol.
  PackSymbol? resolveGlyph(String glyph) {
    final trimmed = glyph.trim();
    if (trimmed.isEmpty) return null;
    for (final s in symbols) {
      for (final g in s.glyphs) {
        if (g == trimmed) return s;
      }
    }
    return null;
  }
}
