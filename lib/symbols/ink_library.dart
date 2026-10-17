import 'symbol_models.dart';

/// Ink library draw ids — full 18-glyph palette (`ink-v1`).
abstract final class InkDrawIds {
  static const circleOpen = 'circle-open';
  static const wave = 'wave';
  static const tripleBar = 'triple-bar';
  static const diamond = 'diamond';
  static const triangle = 'triangle';
  static const dot = 'dot';
  static const dash = 'dash';
  static const squareOpen = 'square-open';
  static const arrow = 'arrow';
  static const cross = 'cross';
  static const plus = 'plus';
  static const asterisk = 'asterisk';
  static const halfCircle = 'half-circle';
  static const chevron = 'chevron';
  static const hook = 'hook';
  static const corner = 'corner';
  static const circleDot = 'circle-dot';
  static const invTriangle = 'inv-triangle';

  /// One-stroke vertical bar — journal (easy on paper).
  static const bar = 'bar';

  static const all = <String>[
    circleOpen,
    wave,
    tripleBar,
    diamond,
    triangle,
    dot,
    dash,
    squareOpen,
    arrow,
    cross,
    plus,
    asterisk,
    halfCircle,
    chevron,
    hook,
    corner,
    circleDot,
    invTriangle,
    bar,
  ];
}

/// Full ink-v1 library (18 glyphs) with suggested defaults.
abstract final class InkLibrary {
  static const ref = 'ink-v1';

  static const glyphs = <DrawGlyph>[
    DrawGlyph(id: InkDrawIds.circleOpen, unicode: '○', label: 'inbox / open'),
    DrawGlyph(id: InkDrawIds.wave, unicode: '∼', label: 'fleeting'),
    DrawGlyph(id: InkDrawIds.tripleBar, unicode: '≡', label: 'literature'),
    DrawGlyph(id: InkDrawIds.diamond, unicode: '◇', label: 'permanent'),
    DrawGlyph(id: InkDrawIds.triangle, unicode: '△', label: 'visual'),
    DrawGlyph(id: InkDrawIds.dot, unicode: '·', label: 'task / bullet'),
    DrawGlyph(id: InkDrawIds.dash, unicode: '–', label: 'plain note'),
    DrawGlyph(id: InkDrawIds.squareOpen, unicode: '□', label: 'event'),
    DrawGlyph(id: InkDrawIds.arrow, unicode: '→', label: 'next / migrate'),
    DrawGlyph(id: InkDrawIds.cross, unicode: '×', label: 'cancel'),
    DrawGlyph(id: InkDrawIds.plus, unicode: '+', label: 'project / add'),
    DrawGlyph(id: InkDrawIds.asterisk, unicode: '∗', label: 'priority'),
    DrawGlyph(id: InkDrawIds.halfCircle, unicode: '◐', label: 'waiting'),
    DrawGlyph(id: InkDrawIds.chevron, unicode: '›', label: 'someday'),
    DrawGlyph(id: InkDrawIds.hook, unicode: 'ʔ', label: 'question'),
    DrawGlyph(id: InkDrawIds.corner, unicode: '⌜', label: 'reference'),
    DrawGlyph(id: InkDrawIds.circleDot, unicode: '◎', label: 'resource'),
    DrawGlyph(id: InkDrawIds.invTriangle, unicode: '▽', label: 'summary'),
    DrawGlyph(id: InkDrawIds.bar, unicode: 'J', label: 'journal'),
  ];

  static DrawGlyph? byId(String id) {
    for (final g in glyphs) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// Suggested PackSymbol when adding [drawId] to a custom pack.
  static PackSymbol suggestedSymbol(String drawId) {
    final g = byId(drawId);
    final unicode = g?.unicode ?? '?';
    switch (drawId) {
      case InkDrawIds.circleOpen:
        return PackSymbol(
          id: 'inbox',
          draw: drawId,
          glyphs: [unicode, 'I'],
          folder: 'inbox',
          output: SymbolOutput.inbox,
        );
      case InkDrawIds.wave:
        return PackSymbol(
          id: 'fleeting',
          draw: drawId,
          glyphs: [unicode, 'F'],
          folder: 'fleeting',
          output: SymbolOutput.markdown,
        );
      case InkDrawIds.tripleBar:
        return PackSymbol(
          id: 'literature',
          draw: drawId,
          glyphs: [unicode, 'L'],
          folder: 'literature',
          output: SymbolOutput.markdown,
        );
      case InkDrawIds.diamond:
        return PackSymbol(
          id: 'permanent',
          draw: drawId,
          glyphs: [unicode, 'P'],
          folder: 'permanent',
          output: SymbolOutput.markdown,
          reviewGate: 'own_words',
        );
      case InkDrawIds.triangle:
        return PackSymbol(
          id: 'visual',
          draw: drawId,
          glyphs: [unicode, 'V'],
          folder: 'mindmaps',
          output: SymbolOutput.canvas,
        );
      case InkDrawIds.dot:
        return PackSymbol(
          id: 'daily-tasks',
          draw: drawId,
          glyphs: [unicode, '•'],
          output: SymbolOutput.dailyNoteAppend,
          section: '## Tasks',
        );
      case InkDrawIds.bar:
        return PackSymbol(
          id: 'journal',
          draw: drawId,
          glyphs: ['J'],
          folder: 'journal',
          output: SymbolOutput.markdown,
        );
      default:
        final slug = drawId.replaceAll('-', '_');
        return PackSymbol(
          id: slug,
          draw: drawId,
          glyphs: [unicode],
          folder: slug,
          output: SymbolOutput.markdown,
        );
    }
  }
}

/// Soft size guidance for custom packs (brief §4.3).
abstract final class PackSizeGuide {
  static const softWarnAbove = 9;
  static const hardSuggestMax = 12;

  static String? sizeMessage(int count) {
    if (count > hardSuggestMax) {
      return 'Hard to learn past $hardSuggestMax — consider splitting packs';
    }
    if (count > softWarnAbove) {
      return 'Getting crowded — 4–8 symbols is the sweet spot';
    }
    return null;
  }
}
