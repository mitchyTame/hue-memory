import 'package:shared_preferences/shared_preferences.dart';

import '../settings/secret_store.dart';

/// Gemini (AI Studio) settings — classify + diagram Flash models.
///
/// Defaults are Flash-class only (no Pro). Key stored like Mistral.
class GeminiSettings {
  const GeminiSettings({
    this.apiKey = '',
    this.consentGiven = false,
    this.useLive = false,
    this.classifyModel = GeminiSettings.defaultClassifyModel,
    this.diagramModel = GeminiSettings.defaultDiagramModel,
  });

  /// Cheap Flash-lite for coordinator classify (+ Test Gemini).
  static const String defaultClassifyModel = 'gemini-3.5-flash-lite';

  /// Flash for diagram → Obsidian Canvas structure.
  static const String defaultDiagramModel = 'gemini-3.6-flash';

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

  /// Router / classify model id (overrideable in Settings).
  final String classifyModel;

  /// Diagram / Canvas structure model id (overrideable in Settings).
  final String diagramModel;

  bool get shouldUseLive =>
      useLive && consentGiven && apiKey.trim().isNotEmpty;

  /// Short label for Settings hub.
  String get modelsLabel =>
      '${_short(classifyModel)} / ${_short(diagramModel)}';

  static String _short(String id) {
    final t = id.trim();
    if (t == defaultClassifyModel) return '3.5-lite';
    if (t == defaultDiagramModel) return '3.6-flash';
    return t;
  }

  GeminiSettings copyWith({
    String? apiKey,
    bool? consentGiven,
    bool? useLive,
    String? classifyModel,
    String? diagramModel,
  }) {
    return GeminiSettings(
      apiKey: apiKey ?? this.apiKey,
      consentGiven: consentGiven ?? this.consentGiven,
      useLive: useLive ?? this.useLive,
      classifyModel: classifyModel ?? this.classifyModel,
      diagramModel: diagramModel ?? this.diagramModel,
    );
  }

  /// Normalize a stored model id — empty / retired → [fallback].
  static String resolveModel(String? raw, String fallback) {
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
  static const keyClassifyModel = 'gemini_classify_model';
  static const keyDiagramModel = 'gemini_diagram_model';

  /// Legacy single-model key from personal-v2 first cut.
  static const keyModelLegacy = 'gemini_model';

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

    final classifyStored = prefs.getString(keyClassifyModel);
    final diagramStored = prefs.getString(keyDiagramModel);
    final legacyModel = prefs.getString(keyModelLegacy);

    // Migrate old single model once: non-retired id seeds both overrides.
    var classify = classifyStored;
    var diagram = diagramStored;
    if ((classify == null || classify.isEmpty) &&
        (diagram == null || diagram.isEmpty) &&
        legacyModel != null &&
        legacyModel.trim().isNotEmpty &&
        !GeminiSettings.retiredModels.contains(legacyModel.trim())) {
      classify = legacyModel;
      diagram = legacyModel;
    }

    return GeminiSettings(
      apiKey: apiKey,
      consentGiven: prefs.getBool(keyConsent) ?? false,
      useLive: prefs.getBool(keyUseLive) ?? false,
      classifyModel: GeminiSettings.resolveModel(
        classify,
        GeminiSettings.defaultClassifyModel,
      ),
      diagramModel: GeminiSettings.resolveModel(
        diagram,
        GeminiSettings.defaultDiagramModel,
      ),
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
      keyClassifyModel,
      GeminiSettings.resolveModel(
        settings.classifyModel,
        GeminiSettings.defaultClassifyModel,
      ),
    );
    await prefs.setString(
      keyDiagramModel,
      GeminiSettings.resolveModel(
        settings.diagramModel,
        GeminiSettings.defaultDiagramModel,
      ),
    );
    // Drop retired legacy single-model key so it cannot resurrect.
    await prefs.remove(keyModelLegacy);
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
