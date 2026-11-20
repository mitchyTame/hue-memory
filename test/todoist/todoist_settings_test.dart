import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/settings/secret_store.dart';
import 'package:hue_memory/todoist/todoist_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('persists Todoist token in secret store, never plaintext prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final secrets = MemorySecretStore();
    final store = PrefsTodoistSettingsStore(secrets: secrets);

    await store.write(const TodoistSettings(apiToken: 'todoist-test-token'));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(PrefsTodoistSettingsStore.keyApiToken), isNull);
    expect(
      await secrets.read(PrefsTodoistSettingsStore.keyApiToken),
      'todoist-test-token',
    );

    final read = await store.read();
    expect(read.hasToken, isTrue);
    expect(read.apiToken, 'todoist-test-token');
  });
}
