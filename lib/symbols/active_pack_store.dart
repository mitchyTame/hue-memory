import 'package:shared_preferences/shared_preferences.dart';

import '../vault/vault_fs.dart';
import 'default_packs.dart';
import 'pack_catalog.dart';
import 'pack_editor.dart';
import 'pack_yaml.dart';
import 'symbol_models.dart';

/// Persists which pack is active and mirrors it into the vault.
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

  /// Legacy vault paths — **no longer written**. Pack config lives in prefs
  /// only so the Obsidian vault is not polluted with `packs/` folders.
  @Deprecated('Pack config is prefs-only; do not write to vault')
  static const vaultMirrorPath = 'symbol-journal/packs/active.yaml';
  @Deprecated('Pack config is prefs-only; do not write to vault')
  static const vaultCustomPath = 'symbol-journal/packs/custom.yaml';

  SharedPreferences? _prefs;
  final PackCatalog _catalog;
  final PackYaml yaml;

  SymbolPack? _cached;

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

  /// Persist custom pack YAML and optionally activate + vault-mirror.
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
    final edited = prefs.getString(keyActivePackYaml);
    if (edited != null && edited.trim().isNotEmpty) {
      try {
        _cached = yaml.parse(edited);
        return _cached!;
      } catch (_) {
        await prefs.remove(keyActivePackYaml);
      }
    }
    final id = await readActivePackId();
    if (id == PackEditor.customPackId) {
      _cached = await customPackOrBlank();
      return _cached!;
    }
    _cached = await _catalog.loadById(id);
    return _cached!;
  }

  /// Persist folder / symbol edits for the active pack (any pack id).
  Future<void> savePackEdits(SymbolPack pack, {VaultFs? vault}) async {
    final prefs = await _ensurePrefs();
    await prefs.setString(keyActivePackYaml, yaml.encode(pack));
    await prefs.setString(keyActivePackId, pack.id);
    if (pack.id == PackEditor.customPackId) {
      await prefs.setString(keyCustomPackYaml, yaml.encode(pack));
    }
    _cached = pack;
    // [vault] kept for call-site compatibility; pack config is prefs-only.
  }

  Future<List<SymbolPack>> availablePacks() async {
    final packs = await _catalog.loadBundled();
    final custom = await readCustomPack() ?? DefaultPacks.blankCustom;
    final without = packs.where((p) => p.id != PackEditor.customPackId).toList();
    without.add(custom);
    return without;
  }

  Future<void> setActivePack(SymbolPack pack, {VaultFs? vault}) async {
    final prefs = await _ensurePrefs();
    await prefs.setString(keyActivePackId, pack.id);
    // Switching packs clears in-progress folder edits for the previous pack.
    await prefs.remove(keyActivePackYaml);
    _cached = pack;
    // Pack config is prefs-only — do not create symbol-journal/packs/ in vault.
  }

  /// No-op retained for call sites. Pack YAML is never written into the vault.
  Future<void> mirrorToVault(VaultFs vault, SymbolPack pack) async {}
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
