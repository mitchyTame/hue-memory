import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/ocr/ocr_settings.dart';
import 'package:hue_memory/settings/secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('API key round-trips through SecretStore, not plaintext prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final secrets = MemorySecretStore();
    final store = PrefsOcrSettingsStore(prefs: prefs, secrets: secrets);

    await store.write(
      const OcrSettings(
        apiKey: 'sk-test-secret',
        consentGiven: true,
        useLive: true,
      ),
    );

    expect(prefs.getString(PrefsOcrSettingsStore.keyApiKey), isNull);
    expect(await secrets.read(PrefsOcrSettingsStore.keyApiKey), 'sk-test-secret');

    final read = await store.read();
    expect(read.apiKey, 'sk-test-secret');
    expect(read.shouldUseLive, isTrue);
  });

  test('migrates legacy plaintext prefs key into secure store', () async {
    SharedPreferences.setMockInitialValues({
      PrefsOcrSettingsStore.keyApiKey: 'legacy-key',
      PrefsOcrSettingsStore.keyConsent: true,
    });
    final prefs = await SharedPreferences.getInstance();
    final secrets = MemorySecretStore();
    final store = PrefsOcrSettingsStore(prefs: prefs, secrets: secrets);

    final read = await store.read();
    expect(read.apiKey, 'legacy-key');
    expect(await secrets.read(PrefsOcrSettingsStore.keyApiKey), 'legacy-key');
    expect(prefs.getString(PrefsOcrSettingsStore.keyApiKey), isNull);
  });
}
