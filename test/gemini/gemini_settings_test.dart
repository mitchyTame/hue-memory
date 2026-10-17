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
    expect(read.model, GeminiSettings.defaultModel);
    expect(read.classifyModel, read.model);
    expect(read.diagramModel, read.model);
    expect(read.apiKey, 'AIza-test-key-not-real');
  });

  test('default and picker options', () {
    expect(GeminiSettings.defaultModel, 'gemini-3.5-flash-lite');
    expect(GeminiSettings.flash36Model, 'gemini-3.6-flash');
    expect(
      GeminiSettings.selectableModels,
      containsAll([
        GeminiSettings.defaultModel,
        GeminiSettings.flash36Model,
      ]),
    );
    expect(
      GeminiSettings.retiredModels.contains('gemini-2.0-flash'),
      isTrue,
    );
    expect(
      GeminiSettings.resolveModel('gemini-2.0-flash'),
      GeminiSettings.defaultModel,
    );
  });

  test('3.6 flash override persists for both roles', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PrefsGeminiSettingsStore(secrets: MemorySecretStore());
    await store.write(
      const GeminiSettings(
        apiKey: 'AIza-x',
        consentGiven: true,
        useLive: true,
        model: GeminiSettings.flash36Model,
      ),
    );
    final read = await store.read();
    expect(read.model, GeminiSettings.flash36Model);
    expect(read.classifyModel, GeminiSettings.flash36Model);
    expect(read.diagramModel, GeminiSettings.flash36Model);
  });

  test('legacy retired single model is ignored', () async {
    SharedPreferences.setMockInitialValues({
      PrefsGeminiSettingsStore.keyModel: 'gemini-2.0-flash',
      PrefsGeminiSettingsStore.keyConsent: true,
      PrefsGeminiSettingsStore.keyUseLive: true,
    });
    final store = PrefsGeminiSettingsStore(secrets: MemorySecretStore());
    final read = await store.read();
    expect(read.model, GeminiSettings.defaultModel);
  });
}
