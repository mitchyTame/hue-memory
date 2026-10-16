import 'package:shared_preferences/shared_preferences.dart';

/// Persists the chosen vault root path (desktop LocalVaultFs / future SAF URI).
abstract interface class VaultSettingsStore {
  Future<String?> readVaultRoot();
  Future<void> writeVaultRoot(String? absolutePath);
}

class PrefsVaultSettingsStore implements VaultSettingsStore {
  PrefsVaultSettingsStore({SharedPreferences? prefs}) : _prefs = prefs;

  static const keyVaultRoot = 'vault_root_path';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensure() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<String?> readVaultRoot() async {
    final prefs = await _ensure();
    return prefs.getString(keyVaultRoot);
  }

  @override
  Future<void> writeVaultRoot(String? absolutePath) async {
    final prefs = await _ensure();
    if (absolutePath == null || absolutePath.isEmpty) {
      await prefs.remove(keyVaultRoot);
    } else {
      await prefs.setString(keyVaultRoot, absolutePath);
    }
  }
}

/// In-memory store for tests.
class MemoryVaultSettingsStore implements VaultSettingsStore {
  String? path;

  @override
  Future<String?> readVaultRoot() async => path;

  @override
  Future<void> writeVaultRoot(String? absolutePath) async {
    path = absolutePath;
  }
}
