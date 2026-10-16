import 'ink_library.dart';
import 'symbol_models.dart';

export 'ink_library.dart' show InkDrawIds;

/// Dart fallback if YAML assets fail to load. Prefer `assets/packs/*.yaml`.
abstract final class DefaultPacks {
  static const SymbolPack zettelkastenInk = SymbolPack(
    id: 'zettelkasten-ink',
    libraryRef: InkLibrary.ref,
    label: 'Zettelkasten ink',
    symbols: [
      PackSymbol(
        id: 'inbox',
        draw: InkDrawIds.circleOpen,
        // · is reserved for daily-tasks in this pack; letter alias I remains.
        glyphs: ['○', 'I'],
        folder: 'inbox',
        output: SymbolOutput.markdown,
      ),
      PackSymbol(
        id: 'fleeting',
        draw: InkDrawIds.wave,
        glyphs: ['∼', 'F'],
        folder: 'fleeting',
        output: SymbolOutput.markdown,
      ),
      PackSymbol(
        id: 'literature',
        draw: InkDrawIds.tripleBar,
        glyphs: ['≡', 'L'],
        folder: 'literature',
        output: SymbolOutput.markdown,
      ),
      PackSymbol(
        id: 'permanent',
        draw: InkDrawIds.diamond,
        glyphs: ['◇', 'P'],
        folder: 'permanent',
        output: SymbolOutput.markdown,
        reviewGate: 'own_words',
      ),
      PackSymbol(
        id: 'visual',
        draw: InkDrawIds.triangle,
        glyphs: ['△', 'V'],
        folder: 'mindmaps',
        output: SymbolOutput.canvas,
      ),
      PackSymbol(
        id: 'daily-tasks',
        draw: InkDrawIds.dot,
        glyphs: ['·', '•'],
        folder: 'Daily Notes',
        output: SymbolOutput.dailyNoteAppend,
        section: '## Tasks',
      ),
    ],
  );

  /// Blank custom pack — ○ inbox only; add from library in Settings.
  static const SymbolPack blankCustom = SymbolPack(
    id: 'blank-custom',
    libraryRef: InkLibrary.ref,
    label: 'Blank custom',
    symbols: [
      PackSymbol(
        id: 'inbox',
        draw: InkDrawIds.circleOpen,
        glyphs: ['○', 'I'],
        folder: 'inbox',
        output: SymbolOutput.inbox,
      ),
    ],
  );
}
