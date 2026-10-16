import 'package:shared_preferences/shared_preferences.dart';

import '../vault/vault_fs.dart';
import 'pack_catalog.dart';
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
  static const vaultMirrorPath = 'symbol-journal/packs/active.yaml';

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

  Future<SymbolPack> activePack() async {
    if (_cached != null) return _cached!;
    final id = await readActivePackId();
    _cached = await _catalog.loadById(id);
    return _cached!;
  }

  Future<List<SymbolPack>> availablePacks() => _catalog.loadBundled();

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
