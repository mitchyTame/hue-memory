import 'ink_library.dart';
import 'symbol_models.dart';

/// Pure helpers for editing a custom symbol pack against the ink library.
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

  /// Remove by symbol id — refuses to drop inbox.
  static SymbolPack removeSymbol(SymbolPack pack, String symbolId) {
    if (symbolId == 'inbox') {
      throw StateError('Cannot remove inbox');
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
