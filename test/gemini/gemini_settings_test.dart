import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/gemini/gemini_settings.dart';
import 'package:hue_memory/settings/secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('persists Gemini key in secret store, never plaintext prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final secrets = MemorySecretStore();
    final store = PrefsGeminiSettingsStore(secrets: secrets);

    await store.write(
      const GeminiSettings(
        apiKey: 'AIza-test-key-not-real',
        consentGiven: true,
        useLive: true,
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PrefsGeminiSettingsStore.keyApiKey), isNull);
    expect(await secrets.read(PrefsGeminiSettingsStore.keyApiKey),
        'AIza-test-key-not-real');

    final read = await store.read();
    expect(read.shouldUseLive, isTrue);
    expect(read.classifyModel, GeminiSettings.defaultClassifyModel);
    expect(read.diagramModel, GeminiSettings.defaultDiagramModel);
    expect(read.apiKey, 'AIza-test-key-not-real');
  });

  test('defaults are current Flash-lite / Flash (not retired 2.x)', () {
    expect(
      GeminiSettings.defaultClassifyModel,
      'gemini-3.5-flash-lite',
    );
    expect(
      GeminiSettings.defaultDiagramModel,
      'gemini-3.6-flash',
    );
    expect(
      GeminiSettings.retiredModels.contains('gemini-2.0-flash'),
      isTrue,
    );
    expect(
      GeminiSettings.resolveModel('gemini-2.0-flash', 'fallback'),
      'fallback',
    );
  });

  test('custom model overrides persist', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PrefsGeminiSettingsStore(secrets: MemorySecretStore());
    await store.write(
      const GeminiSettings(
        apiKey: 'AIza-x',
        consentGiven: true,
        useLive: true,
        classifyModel: 'gemini-custom-lite',
        diagramModel: 'gemini-custom-flash',
      ),
    );
    final read = await store.read();
    expect(read.classifyModel, 'gemini-custom-lite');
    expect(read.diagramModel, 'gemini-custom-flash');
  });

  test('legacy retired single model is ignored', () async {
    SharedPreferences.setMockInitialValues({
      PrefsGeminiSettingsStore.keyModelLegacy: 'gemini-2.0-flash',
      PrefsGeminiSettingsStore.keyConsent: true,
      PrefsGeminiSettingsStore.keyUseLive: true,
    });
    final store = PrefsGeminiSettingsStore(secrets: MemorySecretStore());
    final read = await store.read();
    expect(read.classifyModel, GeminiSettings.defaultClassifyModel);
    expect(read.diagramModel, GeminiSettings.defaultDiagramModel);
  });
}
