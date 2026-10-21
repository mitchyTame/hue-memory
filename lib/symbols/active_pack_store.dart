import 'package:shared_preferences/shared_preferences.dart';

import '../vault/vault_fs.dart';
import 'default_packs.dart';
import 'pack_catalog.dart';
import 'pack_editor.dart';
import 'pack_yaml.dart';
import 'symbol_models.dart';

/// Persists which pack is active in app prefs (never into the Obsidian vault).
///
/// User-added symbols ("extras") are stored per pack id and merged onto the
/// bundled defaults so Zettelkasten / GTD stay intact and additive.
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
    _cached = PackEditor.mergeExtras(base, extras);
    return _cached!;
  }

  /// Persist folder / symbol edits for the active pack (any pack id).
  ///
  /// Extracts and stores extras per pack id so they survive pack switches.
  Future<void> savePackEdits(SymbolPack pack, {VaultFs? vault}) async {
    final prefs = await _ensurePrefs();
    final base = await basePackFor(pack.id);
    final extras = PackEditor.extrasOf(pack, base);
    await saveExtras(pack.id, extras);
    await prefs.setString(keyActivePackYaml, yaml.encode(pack));
    await prefs.setString(keyActivePackId, pack.id);
    if (pack.id == PackEditor.customPackId) {
      // Blank custom: whole pack is user-owned (still prefs-only).
      await prefs.setString(keyCustomPackYaml, yaml.encode(pack));
    }
    _cached = pack;
    // [vault] kept for call-site compatibility; pack config is prefs-only.
  }

  Future<List<SymbolPack>> availablePacks() async {
    final packs = await _catalog.loadBundled();
    final custom = await readCustomPack() ?? DefaultPacks.blankCustom;
    final without = packs.where((p) => p.id != PackEditor.customPackId).toList();
    // Show each bundled pack with its extras merged for Settings previews.
    final withExtras = <SymbolPack>[];
    for (final p in without) {
      final extras = await readExtras(p.id);
      withExtras.add(PackEditor.mergeExtras(p, extras));
    }
    withExtras.add(custom);
    return withExtras;
  }

  Future<void> setActivePack(SymbolPack pack, {VaultFs? vault}) async {
    final prefs = await _ensurePrefs();
    await prefs.setString(keyActivePackId, pack.id);
    // Switching packs clears in-progress folder edits for the previous pack.
    // Extras for each pack id remain in prefs and are re-merged on load.
    await prefs.remove(keyActivePackYaml);
    _cached = null;
    _cached = await activePack();
    // Pack config is prefs-only — do not create symbol-journal/packs/ in vault.
  }

  /// No-op retained for call sites. Pack YAML is never written into the vault.
  Future<void> mirrorToVault(VaultFs vault, SymbolPack pack) async {}

  /// Copy folder (and output/section) overrides from [edited] onto [base]
  /// symbols only — extras are handled separately.
  static SymbolPack _applyBaseFolderOverrides(
    SymbolPack base,
    SymbolPack edited,
  ) {
    final next = <PackSymbol>[];
    for (final s in base.symbols) {
      final override = edited.byId(s.id);
      if (override == null) {
        next.add(s);
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
