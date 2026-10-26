import 'package:shared_preferences/shared_preferences.dart';

import '../vault/vault_fs.dart';
import 'default_packs.dart';
import 'pack_catalog.dart';
import 'pack_editor.dart';
import 'pack_yaml.dart';
import 'symbol_models.dart';

/// Persists which pack is active in app prefs (never into the Obsidian vault).
///
/// User-added symbols ("extras") and removed default ids are stored per pack
/// id so chips / routing stay trimmed until symbols are re-added from the
/// library. Pack YAML is never written under `symbol-journal/packs/`.
class ActivePackStore {
  ActivePackStore({
    SharedPreferences? prefs,
    PackCatalog? catalog,
    this.yaml = const PackYaml(),
  })  : _prefs = prefs,
        _catalog = catalog ?? PackCatalog();

  static const keyActivePackId = 'active_symbol_pack_id';
  static const keyCustomPackYaml = 'custom_symbol_pack_yaml';
  static const keyActivePackYaml = 'active_symbol_pack_yaml';

  /// Prefs key prefix for per-pack extras YAML (`pack_extras_yaml_<id>`).
  static const keyExtrasPrefix = 'pack_extras_yaml_';

  /// Prefs key prefix for removed default symbol ids (`pack_removed_ids_<id>`).
  static const keyRemovedPrefix = 'pack_removed_ids_';

  /// Legacy paths — must never be written. Kept only so tests can assert absence.
  @Deprecated('Pack config is prefs-only; do not write to vault')
  static const vaultMirrorPath = 'symbol-journal/packs/active.yaml';
  @Deprecated('Pack config is prefs-only; do not write to vault')
  static const vaultCustomPath = 'symbol-journal/packs/custom.yaml';

  SharedPreferences? _prefs;
  final PackCatalog _catalog;
  final PackYaml yaml;

  SymbolPack? _cached;

  static String extrasKeyFor(String packId) => '$keyExtrasPrefix$packId';

  static String removedKeyFor(String packId) => '$keyRemovedPrefix$packId';

  Future<SharedPreferences> _ensurePrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<String> readActivePackId() async {
    final prefs = await _ensurePrefs();
    return prefs.getString(keyActivePackId) ?? 'zettelkasten-ink';
  }

  Future<SymbolPack?> readCustomPack() async {
    final prefs = await _ensurePrefs();
    final raw = prefs.getString(keyCustomPackYaml);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return yaml.parse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<SymbolPack> customPackOrBlank() async {
    return await readCustomPack() ?? DefaultPacks.blankCustom;
  }

  /// Load user extras for [packId] (prefs-only).
  Future<List<PackSymbol>> readExtras(String packId) async {
    final prefs = await _ensurePrefs();
    final raw = prefs.getString(extrasKeyFor(packId));
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      return yaml.parseExtras(raw);
    } catch (_) {
      return const [];
    }
  }

  /// Persist extras for [packId] — never writes into the vault.
  Future<void> saveExtras(String packId, List<PackSymbol> extras) async {
    final prefs = await _ensurePrefs();
    final key = extrasKeyFor(packId);
    if (extras.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, yaml.encodeExtras(extras));
    }
  }

  /// Load removed default symbol ids for [packId] (prefs-only).
  Future<List<String>> readRemovedIds(String packId) async {
    final prefs = await _ensurePrefs();
    final raw = prefs.getStringList(removedKeyFor(packId));
    if (raw == null || raw.isEmpty) return const [];
    return List<String>.from(raw.where((id) => id != 'inbox'));
  }

  /// Persist removed default ids — never writes into the vault.
  Future<void> saveRemovedIds(String packId, List<String> removedIds) async {
    final prefs = await _ensurePrefs();
    final key = removedKeyFor(packId);
    final cleaned = removedIds.where((id) => id != 'inbox').toList();
    if (cleaned.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setStringList(key, cleaned);
    }
  }

  /// Bundled / blank base for [packId] (no extras, no folder edits).
  Future<SymbolPack> basePackFor(String packId) async {
    if (packId == PackEditor.customPackId) {
      return customPackOrBlank();
    }
    return _catalog.loadById(packId);
  }

  /// Persist custom pack YAML in prefs and optionally activate.
  Future<void> saveCustomPack(
    SymbolPack pack, {
    VaultFs? vault,
    bool activate = true,
  }) async {
    final custom = pack.copyWith(
      id: PackEditor.customPackId,
      label: pack.label ?? 'Blank custom',
    );
    final prefs = await _ensurePrefs();
    await prefs.setString(keyCustomPackYaml, yaml.encode(custom));
    // Pack YAML stays in app prefs — never write packs/ into the vault.
    if (activate) {
      await setActivePack(custom, vault: vault);
    } else {
      _cached = null;
    }
  }

  Future<SymbolPack> activePack() async {
    if (_cached != null) return _cached!;
    final prefs = await _ensurePrefs();
    final id = await readActivePackId();
    final edited = prefs.getString(keyActivePackYaml);
    if (edited != null && edited.trim().isNotEmpty) {
      try {
        final parsed = yaml.parse(edited);
        if (parsed.id == id) {
          // Folder edits may already include extras; still merge any
          // separately stored extras that are missing (e.g. after upgrade).
          final extras = await readExtras(id);
          final base = await basePackFor(id);
          final fromEdited = PackEditor.extrasOf(parsed, base);
          final mergedExtras = _dedupeExtras([...fromEdited, ...extras]);
          await saveExtras(id, mergedExtras);
          final removed = PackEditor.removedBaseIds(parsed, base);
          await saveRemovedIds(id, removed);
          _cached = PackEditor.mergeExtras(
            _applyBaseFolderOverrides(base, parsed),
            mergedExtras,
          );
          return _cached!;
        }
      } catch (_) {
        await prefs.remove(keyActivePackYaml);
      }
    }
    final base = await basePackFor(id);
    final extras = await readExtras(id);
    final removed = await readRemovedIds(id);
    _cached = PackEditor.mergeExtras(
      PackEditor.withoutIds(base, removed),
      extras,
    );
    return _cached!;
  }

  /// Persist folder / symbol edits for the active pack (any pack id).
  ///
  /// Extracts and stores extras + removed default ids per pack id so they
  /// survive pack switches. Never writes `symbol-journal/packs/` to the vault.
  Future<void> savePackEdits(SymbolPack pack, {VaultFs? vault}) async {
    final prefs = await _ensurePrefs();
    final base = await basePackFor(pack.id);
    final extras = PackEditor.extrasOf(pack, base);
    final removed = PackEditor.removedBaseIds(pack, base);
    await saveExtras(pack.id, extras);
    await saveRemovedIds(pack.id, removed);
    await prefs.setString(keyActivePackYaml, yaml.encode(pack));
    await prefs.setString(keyActivePackId, pack.id);
    if (pack.id == PackEditor.customPackId) {
      // Blank custom: whole pack is user-owned (still prefs-only).
      await prefs.setString(keyCustomPackYaml, yaml.encode(pack));
    }
    _cached = pack;
    // [vault] kept for call-site compatibility; pack config is prefs-only.
  }

  /// Re-add all removed defaults for [packId] (extras kept). Prefs-only.
  Future<SymbolPack> restoreRemovedDefaults(String packId) async {
    await saveRemovedIds(packId, const []);
    final prefs = await _ensurePrefs();
    // Drop stale full-pack YAML so base symbols return on next load.
    final edited = prefs.getString(keyActivePackYaml);
    if (edited != null && edited.trim().isNotEmpty) {
      try {
        final parsed = yaml.parse(edited);
        if (parsed.id == packId) {
          final base = await basePackFor(packId);
          final extras = PackEditor.extrasOf(parsed, base);
          final restored = PackEditor.mergeExtras(
            _applyBaseFolderOverrides(base, parsed, includeMissing: true),
            extras,
          );
          await prefs.setString(keyActivePackYaml, yaml.encode(restored));
          _cached = null;
          return await activePack();
        }
      } catch (_) {
        await prefs.remove(keyActivePackYaml);
      }
    }
    _cached = null;
    return await activePack();
  }

  Future<List<SymbolPack>> availablePacks() async {
    final packs = await _catalog.loadBundled();
    final custom = await readCustomPack() ?? DefaultPacks.blankCustom;
    final without = packs.where((p) => p.id != PackEditor.customPackId).toList();
    // Show each bundled pack with extras + removals for Settings previews.
    final withExtras = <SymbolPack>[];
    for (final p in without) {
      final extras = await readExtras(p.id);
      final removed = await readRemovedIds(p.id);
      withExtras.add(
        PackEditor.mergeExtras(PackEditor.withoutIds(p, removed), extras),
      );
    }
    withExtras.add(custom);
    return withExtras;
  }

  Future<void> setActivePack(SymbolPack pack, {VaultFs? vault}) async {
    final prefs = await _ensurePrefs();
    await prefs.setString(keyActivePackId, pack.id);
    // Switching packs clears in-progress folder edits for the previous pack.
    // Extras + removed ids for each pack id remain and are re-merged on load.
    await prefs.remove(keyActivePackYaml);
    _cached = null;
    _cached = await activePack();
    // Pack config is prefs-only — do not create symbol-journal/packs/ in vault.
  }

  /// No-op retained for call sites. Pack YAML is never written into the vault.
  Future<void> mirrorToVault(VaultFs vault, SymbolPack pack) async {}

  /// Copy folder / output / section overrides from [edited] onto [base]
  /// symbols that still appear in [edited]. Missing base symbols stay removed
  /// unless [includeMissing] is true (restore-defaults path).
  static SymbolPack _applyBaseFolderOverrides(
    SymbolPack base,
    SymbolPack edited, {
    bool includeMissing = false,
  }) {
    final next = <PackSymbol>[];
    for (final s in base.symbols) {
      final override = edited.byId(s.id);
      if (override == null) {
        if (includeMissing) next.add(s);
        continue;
      }
      next.add(
        s.copyWith(
          folder: override.folder,
          clearFolder: override.folder == null,
          output: override.output,
          section: override.section,
          clearSection: override.section == null,
          reviewGate: override.reviewGate,
          clearReviewGate: override.reviewGate == null,
        ),
      );
    }
    return base.copyWith(symbols: next);
  }

  static List<PackSymbol> _dedupeExtras(List<PackSymbol> extras) {
    final seenIds = <String>{};
    final seenDraws = <String>{};
    final out = <PackSymbol>[];
    for (final e in extras) {
      if (seenIds.contains(e.id) || seenDraws.contains(e.draw)) continue;
      seenIds.add(e.id);
      seenDraws.add(e.draw);
      out.add(e);
    }
    return out;
  }
}

/// In-memory store for tests.
class MemoryActivePackStore {
  MemoryActivePackStore(this.pack);

  SymbolPack pack;

  Future<SymbolPack> activePack() async => pack;

  Future<void> setActivePack(SymbolPack next) async {
    pack = next;
  }
}
