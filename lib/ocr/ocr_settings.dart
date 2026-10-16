import 'package:shared_preferences/shared_preferences.dart';

import '../settings/secret_store.dart';

class OcrSettings {
  const OcrSettings({
    this.apiKey = '',
    this.consentGiven = false,
    this.useLive = false,
  });

  final String apiKey;
  final bool consentGiven;

  /// When true (and consent + key present), call Mistral instead of mock.
  final bool useLive;

  bool get shouldUseLive =>
      useLive && consentGiven && apiKey.trim().isNotEmpty;

  OcrSettings copyWith({
    String? apiKey,
    bool? consentGiven,
    bool? useLive,
  }) {
    return OcrSettings(
      apiKey: apiKey ?? this.apiKey,
      consentGiven: consentGiven ?? this.consentGiven,
      useLive: useLive ?? this.useLive,
    );
  }
}

abstract interface class OcrSettingsStore {
  Future<OcrSettings> read();
  Future<void> write(OcrSettings settings);
}

class PrefsOcrSettingsStore implements OcrSettingsStore {
  PrefsOcrSettingsStore({
    SharedPreferences? prefs,
    SecretStore? secrets,
    this.envApiKey = '',
  })  : _prefs = prefs,
        _secrets = secrets ?? FlutterSecretStore();

  static const keyApiKey = 'ocr_mistral_api_key';
  static const keyConsent = 'ocr_mistral_consent';
  static const keyUseLive = 'ocr_mistral_use_live';

  /// Optional process env / --dart-define override (never logged).
  final String envApiKey;
  SharedPreferences? _prefs;
  final SecretStore _secrets;

  Future<SharedPreferences> _ensure() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<OcrSettings> read() async {
    final prefs = await _ensure();
    var stored = await _secrets.read(keyApiKey) ?? '';
    // One-shot migrate from legacy plaintext prefs → secure store.
    if (stored.isEmpty) {
      final legacy = prefs.getString(keyApiKey) ?? '';
      if (legacy.isNotEmpty) {
        await _secrets.write(keyApiKey, legacy);
        await prefs.remove(keyApiKey);
        stored = legacy;
      }
    }
    final apiKey = envApiKey.trim().isNotEmpty ? envApiKey.trim() : stored;

    return OcrSettings(
      apiKey: apiKey,
      consentGiven: prefs.getBool(keyConsent) ?? false,
      useLive: prefs.getBool(keyUseLive) ?? false,
    );
  }

  @override
  Future<void> write(OcrSettings settings) async {
    final prefs = await _ensure();
    final key = settings.apiKey.trim();
    if (key.isEmpty) {
      await _secrets.delete(keyApiKey);
    } else {
      await _secrets.write(keyApiKey, key);
    }
    // Never leave a plaintext copy behind.
    await prefs.remove(keyApiKey);
    await prefs.setBool(keyConsent, settings.consentGiven);
    await prefs.setBool(keyUseLive, settings.useLive);
  }
}

class MemoryOcrSettingsStore implements OcrSettingsStore {
  MemoryOcrSettingsStore([this.value = const OcrSettings()]);

  OcrSettings value;

  @override
  Future<OcrSettings> read() async => value;

  @override
  Future<void> write(OcrSettings settings) async {
    value = settings;
  }
}
