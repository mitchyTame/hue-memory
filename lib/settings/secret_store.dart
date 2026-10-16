import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Small secret vault for API keys (platform keychain / encrypted prefs).
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Production: Android Keystore / iOS Keychain / desktop libsecret when available.
class FlutterSecretStore implements SecretStore {
  FlutterSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// In-memory secrets for tests.
class MemorySecretStore implements SecretStore {
  MemorySecretStore([Map<String, String>? seed])
      : _map = Map<String, String>.from(seed ?? const {});

  final Map<String, String> _map;

  @override
  Future<String?> read(String key) async => _map[key];

  @override
  Future<void> write(String key, String value) async {
    _map[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _map.remove(key);
  }
}
