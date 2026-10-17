import 'package:shared_preferences/shared_preferences.dart';

import '../settings/secret_store.dart';

/// Gemini (AI Studio) settings — classify + diagram Flash models.
///
/// Default model is Flash-class only (no Pro). Key stored like Mistral.
class GeminiSettings {
  const GeminiSettings({
    this.apiKey = '',
    this.consentGiven = false,
    this.useLive = false,
    this.model = GeminiSettings.defaultModel,
  });

  /// Stable Flash model accepted by AI Studio `AIza…` keys.
  static const String defaultModel = 'gemini-2.0-flash';

  final String apiKey;
  final bool consentGiven;

  /// When true (and consent + key), run Gemini classify / diagram.
  final bool useLive;

  /// Flash-class model id (classify + diagram share this).
  final String model;

  bool get shouldUseLive =>
      useLive && consentGiven && apiKey.trim().isNotEmpty;

  GeminiSettings copyWith({
    String? apiKey,
    bool? consentGiven,
    bool? useLive,
    String? model,
  }) {
    return GeminiSettings(
      apiKey: apiKey ?? this.apiKey,
      consentGiven: consentGiven ?? this.consentGiven,
      useLive: useLive ?? this.useLive,
      model: model ?? this.model,
    );
  }
}

abstract interface class GeminiSettingsStore {
  Future<GeminiSettings> read();
  Future<void> write(GeminiSettings settings);
}

class PrefsGeminiSettingsStore implements GeminiSettingsStore {
  PrefsGeminiSettingsStore({
    SharedPreferences? prefs,
    SecretStore? secrets,
    this.envApiKey = '',
  })  : _prefs = prefs,
        _secrets = secrets ?? FlutterSecretStore();

  static const keyApiKey = 'gemini_api_key';
  static const keyConsent = 'gemini_consent';
  static const keyUseLive = 'gemini_use_live';
  static const keyModel = 'gemini_model';

  /// Optional process env / --dart-define override (never logged).
  final String envApiKey;
  SharedPreferences? _prefs;
  final SecretStore _secrets;

  Future<SharedPreferences> _ensure() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<GeminiSettings> read() async {
    final prefs = await _ensure();
    var stored = await _secrets.read(keyApiKey) ?? '';
    if (stored.isEmpty) {
      final legacy = prefs.getString(keyApiKey) ?? '';
      if (legacy.isNotEmpty) {
        await _secrets.write(keyApiKey, legacy);
        await prefs.remove(keyApiKey);
        stored = legacy;
      }
    }
    final apiKey = envApiKey.trim().isNotEmpty ? envApiKey.trim() : stored;
    final model = prefs.getString(keyModel)?.trim();
    return GeminiSettings(
      apiKey: apiKey,
      consentGiven: prefs.getBool(keyConsent) ?? false,
      useLive: prefs.getBool(keyUseLive) ?? false,
      model: (model == null || model.isEmpty)
          ? GeminiSettings.defaultModel
          : model,
    );
  }

  @override
  Future<void> write(GeminiSettings settings) async {
    final prefs = await _ensure();
    final key = settings.apiKey.trim();
    if (key.isEmpty) {
      await _secrets.delete(keyApiKey);
    } else {
      await _secrets.write(keyApiKey, key);
    }
    await prefs.remove(keyApiKey);
    await prefs.setBool(keyConsent, settings.consentGiven);
    await prefs.setBool(keyUseLive, settings.useLive);
    await prefs.setString(
      keyModel,
      settings.model.trim().isEmpty
          ? GeminiSettings.defaultModel
          : settings.model.trim(),
    );
  }
}

class MemoryGeminiSettingsStore implements GeminiSettingsStore {
  MemoryGeminiSettingsStore([this.value = const GeminiSettings()]);

  GeminiSettings value;

  @override
  Future<GeminiSettings> read() async => value;

  @override
  Future<void> write(GeminiSettings settings) async {
    value = settings;
  }
}
