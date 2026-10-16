import 'symbol_models.dart';

/// Ink library draw ids used by the ZK default pack.
abstract final class InkDrawIds {
  static const circleOpen = 'circle-open';
  static const wave = 'wave';
  static const tripleBar = 'triple-bar';
  static const diamond = 'diamond';
  static const triangle = 'triangle';
  static const dot = 'dot';
}

/// Default Zettelkasten ink pack: ○ ∼ ≡ ◇ △ ·
abstract final class DefaultPacks {
  static const SymbolPack zettelkastenInk = SymbolPack(
    id: 'zettelkasten-ink',
    libraryRef: 'ink-v1',
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
        output: SymbolOutput.dailyNoteAppend,
        section: '## Tasks',
      ),
    ],
  );
}
