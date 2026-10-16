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
  static const vaultMirrorPath = 'symbol-journal/packs/active.yaml';
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
    if (vault != null) {
      await vault.writeText(vaultCustomPath, yaml.encode(custom));
    }
    if (activate) {
      await setActivePack(custom, vault: vault);
    } else {
      _cached = null;
    }
  }

  Future<SymbolPack> activePack() async {
    if (_cached != null) return _cached!;
    final id = await readActivePackId();
    if (id == PackEditor.customPackId) {
      _cached = await customPackOrBlank();
      return _cached!;
    }
    _cached = await _catalog.loadById(id);
    return _cached!;
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
    _cached = pack;
    if (vault != null) {
      await mirrorToVault(vault, pack);
    }
  }

  Future<void> mirrorToVault(VaultFs vault, SymbolPack pack) async {
    await vault.writeText(vaultMirrorPath, yaml.encode(pack));
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
