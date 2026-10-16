import 'package:shared_preferences/shared_preferences.dart';

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
    this.envApiKey = '',
  }) : _prefs = prefs;

  static const keyApiKey = 'ocr_mistral_api_key';
  static const keyConsent = 'ocr_mistral_consent';
  static const keyUseLive = 'ocr_mistral_use_live';

  /// Optional process env / --dart-define override (never logged).
  final String envApiKey;
  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensure() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<OcrSettings> read() async {
    final prefs = await _ensure();
    final stored = prefs.getString(keyApiKey) ?? '';
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
    await prefs.setString(keyApiKey, settings.apiKey);
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
