import 'ink_library.dart';
import 'symbol_models.dart';

/// Pure helpers for editing a symbol pack against the ink library.
///
/// Default packs (Zettelkasten, GTD, …) stay intact — extras are additive.
/// [blank-custom] still requires inbox and may remove any non-inbox symbol.
abstract final class PackEditor {
  static const customPackId = 'blank-custom';

  /// Add [symbol] if draw id not already present; inbox always kept.
  static SymbolPack addSymbol(SymbolPack pack, PackSymbol symbol) {
    if (pack.symbols.any((s) => s.draw == symbol.draw)) {
      throw StateError('Draw ${symbol.draw} already in pack');
    }
    if (pack.symbols.any((s) => s.id == symbol.id)) {
      throw StateError('Symbol id ${symbol.id} already in pack');
    }
    return pack.copyWith(symbols: [...pack.symbols, symbol]);
  }

  /// Build a user extra from a library glyph + label + folder.
  static PackSymbol extraFromLibrary({
    required String drawId,
    required String label,
    required String folder,
    SymbolOutput output = SymbolOutput.markdown,
  }) {
    final g = InkLibrary.byId(drawId);
    if (g == null) {
      throw StateError('Unknown library glyph: $drawId');
    }
    final id = slugifyLabel(label);
    if (id.isEmpty) {
      throw StateError('Label must yield a non-empty id');
    }
    final folderTrim = folder.trim();
    if (folderTrim.isEmpty && output != SymbolOutput.dailyNoteAppend) {
      throw StateError('Vault folder is required');
    }
    return PackSymbol(
      id: id,
      draw: drawId,
      glyphs: [g.unicode],
      folder: folderTrim.isEmpty ? null : folderTrim,
      output: output,
      section: output == SymbolOutput.dailyNoteAppend ? '## Tasks' : null,
    );
  }

  /// Kebab-case id from a human label (`Organising Misc` → `organising-misc`).
  static String slugifyLabel(String label) {
    final lower = label.trim().toLowerCase();
    final slug = lower
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return slug;
  }

  /// Symbols in [pack] that are not part of [base] (by id).
  static List<PackSymbol> extrasOf(SymbolPack pack, SymbolPack base) {
    final baseIds = base.symbols.map((s) => s.id).toSet();
    return pack.symbols.where((s) => !baseIds.contains(s.id)).toList();
  }

  /// Append [extras] onto [base] (skipping draw/id collisions with base).
  static SymbolPack mergeExtras(SymbolPack base, List<PackSymbol> extras) {
    if (extras.isEmpty) return base;
    var next = base;
    for (final extra in extras) {
      if (next.symbols.any((s) => s.draw == extra.draw || s.id == extra.id)) {
        continue;
      }
      next = addSymbol(next, extra);
    }
    return next;
  }

  /// Whether [symbolId] belongs to the bundled/base pack (not a user extra).
  static bool isBaseSymbol(SymbolPack base, String symbolId) =>
      base.byId(symbolId) != null;

  /// Remove by symbol id.
  ///
  /// Always refuses inbox. When [base] is set, also refuses base/default
  /// symbols so extras stay additive and defaults stay intact.
  static SymbolPack removeSymbol(
    SymbolPack pack,
    String symbolId, {
    SymbolPack? base,
  }) {
    if (symbolId == 'inbox') {
      throw StateError('Cannot remove inbox');
    }
    if (base != null && isBaseSymbol(base, symbolId)) {
      throw StateError('Cannot remove default symbol: $symbolId');
    }
    final next = pack.symbols.where((s) => s.id != symbolId).toList();
    if (next.length == pack.symbols.length) {
      throw StateError('Unknown symbol: $symbolId');
    }
    return pack.copyWith(symbols: next);
  }

  /// Replace an existing symbol (by id).
  static SymbolPack updateSymbol(SymbolPack pack, PackSymbol symbol) {
    final i = pack.symbols.indexWhere((s) => s.id == symbol.id);
    if (i < 0) throw StateError('Unknown symbol: ${symbol.id}');
    final next = [...pack.symbols];
    next[i] = symbol;
    return pack.copyWith(symbols: next);
  }

  static Set<String> usedDrawIds(SymbolPack pack) =>
      pack.symbols.map((s) => s.draw).toSet();

  static List<DrawGlyph> availableLibraryGlyphs(SymbolPack pack) {
    final used = usedDrawIds(pack);
    return InkLibrary.glyphs.where((g) => !used.contains(g.id)).toList();
  }
}

extension PackSymbolCopy on PackSymbol {
  PackSymbol copyWith({
    String? id,
    String? draw,
    List<String>? glyphs,
    SymbolOutput? output,
    String? folder,
    String? section,
    String? reviewGate,
    bool clearFolder = false,
    bool clearSection = false,
    bool clearReviewGate = false,
  }) {
    return PackSymbol(
      id: id ?? this.id,
      draw: draw ?? this.draw,
      glyphs: glyphs ?? this.glyphs,
      output: output ?? this.output,
      folder: clearFolder ? null : (folder ?? this.folder),
      section: clearSection ? null : (section ?? this.section),
      reviewGate: clearReviewGate ? null : (reviewGate ?? this.reviewGate),
    );
  }
}

extension SymbolPackCopy on SymbolPack {
  SymbolPack copyWith({
    String? id,
    String? libraryRef,
    String? label,
    List<PackSymbol>? symbols,
  }) {
    return SymbolPack(
      id: id ?? this.id,
      libraryRef: libraryRef ?? this.libraryRef,
      label: label ?? this.label,
      symbols: symbols ?? this.symbols,
    );
  }
}
