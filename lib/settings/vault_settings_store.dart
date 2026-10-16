import 'package:shared_preferences/shared_preferences.dart';

/// Persists the chosen vault root: filesystem path ([LocalVaultFs]) or SAF
/// `content://` tree URI ([SafVaultFs]).
abstract interface class VaultSettingsStore {
  Future<String?> readVaultRoot();
  Future<void> writeVaultRoot(String? absolutePathOrTreeUri);
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
  Future<void> writeVaultRoot(String? absolutePathOrTreeUri) async {
    final prefs = await _ensure();
    if (absolutePathOrTreeUri == null || absolutePathOrTreeUri.isEmpty) {
      await prefs.remove(keyVaultRoot);
    } else {
      await prefs.setString(keyVaultRoot, absolutePathOrTreeUri);
    }
  }
}

/// In-memory store for tests.
class MemoryVaultSettingsStore implements VaultSettingsStore {
  String? path;

  @override
  Future<String?> readVaultRoot() async => path;

  @override
  Future<void> writeVaultRoot(String? absolutePathOrTreeUri) async {
    path = absolutePathOrTreeUri;
  }
}
