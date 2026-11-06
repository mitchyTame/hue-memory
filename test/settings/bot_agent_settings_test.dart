import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/settings/bot_agent_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults to off with inbox folder', () {
    const s = BotAgentSettings();
    expect(s.enabled, isFalse);
    expect(s.inboxFolder, 'inbox');
    expect(s.normalizedInboxFolder, 'inbox');
  });

  test('normalizedInboxFolder accepts nested vault paths', () {
    const s = BotAgentSettings(enabled: true, inboxFolder: 'Bot/Inbox');
    expect(s.normalizedInboxFolder, 'Bot/Inbox');
  });

  test('normalizedInboxFolder falls back on empty / junk', () {
    expect(
      const BotAgentSettings(inboxFolder: '  ').normalizedInboxFolder,
      'inbox',
    );
    expect(
      const BotAgentSettings(inboxFolder: 'hue-memory/inbox')
          .normalizedInboxFolder,
      'inbox',
    );
  });

  test('prefs store persists mode + inbox path', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PrefsBotAgentSettingsStore();

    await store.write(
      const BotAgentSettings(enabled: true, inboxFolder: 'Bot/Inbox'),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(PrefsBotAgentSettingsStore.keyEnabled), isTrue);
    expect(
      prefs.getString(PrefsBotAgentSettingsStore.keyInboxFolder),
      'Bot/Inbox',
    );

    final read = await store.read();
    expect(read.enabled, isTrue);
    expect(read.inboxFolder, 'Bot/Inbox');
    expect(read.normalizedInboxFolder, 'Bot/Inbox');
  });

  test('prefs store empty folder becomes default inbox', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PrefsBotAgentSettingsStore();
    await store.write(
      const BotAgentSettings(enabled: true, inboxFolder: '   '),
    );
    final read = await store.read();
    expect(read.inboxFolder, 'inbox');
  });

  test('memory store round-trips', () async {
    final store = MemoryBotAgentSettingsStore();
    expect((await store.read()).enabled, isFalse);
    await store.write(
      const BotAgentSettings(enabled: true, inboxFolder: 'scans'),
    );
    expect((await store.read()).enabled, isTrue);
    expect((await store.read()).inboxFolder, 'scans');
  });
}
