import 'package:shared_preferences/shared_preferences.dart';

import '../settings/secret_store.dart';

/// Gemini (AI Studio) settings — one Flash model for classify + diagram.
///
/// Default is Flash-lite. Key stored like Mistral.
class GeminiSettings {
  const GeminiSettings({
    this.apiKey = '',
    this.consentGiven = false,
    this.useLive = false,
    this.model = GeminiSettings.defaultModel,
  });

  /// Default for router, mindmaps, and Test Gemini.
  static const String defaultModel = 'gemini-3.5-flash-lite';

  /// Optional stronger Flash Mitch can pick in Settings.
  static const String flash36Model = 'gemini-3.6-flash';

  /// Clear picker options in Settings (defaults first).
  static const List<String> selectableModels = [
    defaultModel,
    flash36Model,
  ];

  /// Retired AI Studio ids — never recommend; treat legacy prefs as unset.
  static const Set<String> retiredModels = {
    'gemini-2.0-flash',
    'gemini-2.0-flash-lite',
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
  };

  final String apiKey;
  final bool consentGiven;

  /// When true (and consent + key), run Gemini classify / diagram.
  final bool useLive;

  /// Shared model for classify, diagram Canvas, and Test Gemini.
  final String model;

  /// Same as [model] — kept so coordinator / client call sites stay clear.
  String get classifyModel => model;
  String get diagramModel => model;

  bool get shouldUseLive =>
      useLive && consentGiven && apiKey.trim().isNotEmpty;

  /// Short label for Settings hub.
  String get modelsLabel {
    final t = model.trim();
    if (t == defaultModel) return '3.5-lite';
    if (t == flash36Model) return '3.6-flash';
    return t;
  }

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

  /// Normalize a stored model id — empty / retired → [fallback].
  static String resolveModel(String? raw, [String fallback = defaultModel]) {
    final t = raw?.trim() ?? '';
    if (t.isEmpty || retiredModels.contains(t)) return fallback;
    return t;
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

  /// Brief split-key era (classify vs diagram) — migrated on read.
  static const keyClassifyModel = 'gemini_classify_model';
  static const keyDiagramModel = 'gemini_diagram_model';

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

    final single = prefs.getString(keyModel);
    final classify = prefs.getString(keyClassifyModel);
    final diagram = prefs.getString(keyDiagramModel);
    // Prefer explicit shared key; else either split key (same default anyway).
    final raw = (single != null && single.trim().isNotEmpty)
        ? single
        : (classify != null && classify.trim().isNotEmpty)
            ? classify
            : diagram;

    return GeminiSettings(
      apiKey: apiKey,
      consentGiven: prefs.getBool(keyConsent) ?? false,
      useLive: prefs.getBool(keyUseLive) ?? false,
      model: GeminiSettings.resolveModel(raw),
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
    final model = GeminiSettings.resolveModel(settings.model);
    await prefs.setString(keyModel, model);
    // Keep split keys in sync for any stale readers; both = shared model.
    await prefs.setString(keyClassifyModel, model);
    await prefs.setString(keyDiagramModel, model);
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
