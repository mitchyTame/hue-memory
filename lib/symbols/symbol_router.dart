import 'default_packs.dart';
import 'symbol_models.dart';

/// Result of routing a detected (or confirmed) symbol to a vault destination.
class RouteResult {
  const RouteResult({
    required this.symbol,
    required this.output,
    this.folder,
    this.section,
  });

  final PackSymbol symbol;
  final SymbolOutput output;
  final String? folder;
  final String? section;

  bool get isDailyTasks => output == SymbolOutput.dailyNoteAppend;
  bool get isCanvas => output == SymbolOutput.canvas;
  bool get isMarkdown =>
      output == SymbolOutput.markdown || output == SymbolOutput.inbox;
}

/// Maps circled ink icons / aliases → pack symbol + folder / output kind.
class SymbolRouter {
  SymbolRouter({SymbolPack? pack}) : pack = pack ?? DefaultPacks.zettelkastenInk;

  final SymbolPack pack;

  /// Ambiguous or unknown glyphs fall back to inbox.
  RouteResult route(String glyph) {
    final resolved = pack.resolveGlyph(glyph);
    if (resolved == null) {
      final inbox = pack.byId('inbox');
      if (inbox == null) {
        throw StateError('Pack ${pack.id} missing required inbox symbol');
      }
      return RouteResult(
        symbol: inbox,
        output: inbox.output,
        folder: inbox.folder,
        section: inbox.section,
      );
    }

    // Bare · aliases inbox in YAML glyphs for inbox, but daily-tasks also
    // lists ·. Prefer daily-tasks when the active pack includes it and the
    // caller passes the dedicated daily-tasks id or we disambiguate via
    // [routeById]. For raw glyph ·, prefer daily-tasks over inbox.
    if (glyph.trim() == '·' || glyph.trim() == '•') {
      final daily = pack.byId('daily-tasks');
      if (daily != null) {
        return RouteResult(
          symbol: daily,
          output: daily.output,
          folder: daily.folder,
          section: daily.section,
        );
      }
    }

    return RouteResult(
      symbol: resolved,
      output: resolved.output,
      folder: resolved.folder,
      section: resolved.section,
    );
  }

  RouteResult routeById(String symbolId) {
    final symbol = pack.byId(symbolId);
    if (symbol == null) {
      return route('○'); // inbox fallback
    }
    return RouteResult(
      symbol: symbol,
      output: symbol.output,
      folder: symbol.folder,
      section: symbol.section,
    );
  }

  /// Relative note path stem under the symbol folder (caller adds slug + ext).
  String noteRelativeDir(RouteResult route) {
    if (route.isDailyTasks) {
      throw ArgumentError('Daily tasks do not use a symbol folder');
    }
    final folder = route.folder;
    if (folder == null || folder.isEmpty) {
      throw StateError('Route ${route.symbol.id} has no folder');
    }
    return folder;
  }
}
