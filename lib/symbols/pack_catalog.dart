import 'package:flutter/services.dart';

import 'default_packs.dart';
import 'pack_yaml.dart';
import 'symbol_models.dart';

/// Bundled pack asset paths (Settings → Symbols).
abstract final class PackAssets {
  static const zettelkasten = 'assets/packs/zettelkasten-ink.yaml';
  static const gtd = 'assets/packs/gtd-ink.yaml';

  static const all = <String>[zettelkasten, gtd];
}

/// Loads symbol packs from Flutter assets (with Dart fallback).
class PackCatalog {
  PackCatalog({
    AssetBundle? bundle,
    this.yaml = const PackYaml(),
  }) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final PackYaml yaml;

  Future<List<SymbolPack>> loadBundled() async {
    final packs = <SymbolPack>[];
    for (final path in PackAssets.all) {
      try {
        final source = await _bundle.loadString(path);
        packs.add(yaml.parse(source));
      } catch (_) {
        // Skip missing/broken assets; fallback added below if needed.
      }
    }
    if (packs.isEmpty) {
      packs.add(DefaultPacks.zettelkastenInk);
    } else if (packs.every((p) => p.id != DefaultPacks.zettelkastenInk.id)) {
      packs.insert(0, DefaultPacks.zettelkastenInk);
    }
    return packs;
  }

  Future<SymbolPack> loadById(String packId) async {
    final packs = await loadBundled();
    for (final p in packs) {
      if (p.id == packId) return p;
    }
    return DefaultPacks.zettelkastenInk;
  }
}
