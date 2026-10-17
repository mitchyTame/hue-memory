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
        model: 'gemini-2.0-flash',
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PrefsGeminiSettingsStore.keyApiKey), isNull);
    expect(await secrets.read(PrefsGeminiSettingsStore.keyApiKey),
        'AIza-test-key-not-real');

    final read = await store.read();
    expect(read.shouldUseLive, isTrue);
    expect(read.model, GeminiSettings.defaultModel);
    expect(read.apiKey, 'AIza-test-key-not-real');
  });

  test('default model is Flash-class', () {
    expect(GeminiSettings.defaultModel, contains('flash'));
    expect(GeminiSettings.defaultModel.toLowerCase(), isNot(contains('pro')));
  });
}
