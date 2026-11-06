import 'package:shared_preferences/shared_preferences.dart';

import '../vault/vault_paths.dart';

/// Bot agent mode — scan photos straight into a vault inbox folder.
///
/// Prefs-only (no vault pack scaffolding). When [enabled], the app skips OCR,
/// Gemini, Canvas, and markdown; it only writes the image file.
class BotAgentSettings {
  const BotAgentSettings({
    this.enabled = false,
    this.inboxFolder = BotAgentSettings.defaultInboxFolder,
  });

  /// Default nested vault path when unset.
  static const String defaultInboxFolder = 'inbox';

  final bool enabled;

  /// Typed nested vault path, e.g. `inbox` or `Bot/Inbox`.
  final String inboxFolder;

  /// Normalized folder for vault writes (never empty when enabled).
  String get normalizedInboxFolder {
    try {
      return normalizeVaultFolder(inboxFolder) ?? defaultInboxFolder;
    } catch (_) {
      return defaultInboxFolder;
    }
  }

  BotAgentSettings copyWith({
    bool? enabled,
    String? inboxFolder,
  }) {
    return BotAgentSettings(
      enabled: enabled ?? this.enabled,
      inboxFolder: inboxFolder ?? this.inboxFolder,
    );
  }
}

abstract interface class BotAgentSettingsStore {
  Future<BotAgentSettings> read();
  Future<void> write(BotAgentSettings settings);
}

class PrefsBotAgentSettingsStore implements BotAgentSettingsStore {
  PrefsBotAgentSettingsStore({SharedPreferences? prefs}) : _prefs = prefs;

  static const keyEnabled = 'bot_agent_enabled';
  static const keyInboxFolder = 'bot_agent_inbox_folder';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _ensure() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<BotAgentSettings> read() async {
    final prefs = await _ensure();
    final rawFolder = prefs.getString(keyInboxFolder);
    final folder = (rawFolder == null || rawFolder.trim().isEmpty)
        ? BotAgentSettings.defaultInboxFolder
        : rawFolder.trim();
    return BotAgentSettings(
      enabled: prefs.getBool(keyEnabled) ?? false,
      inboxFolder: folder,
    );
  }

  @override
  Future<void> write(BotAgentSettings settings) async {
    final prefs = await _ensure();
    await prefs.setBool(keyEnabled, settings.enabled);
    final folder = settings.inboxFolder.trim().isEmpty
        ? BotAgentSettings.defaultInboxFolder
        : settings.inboxFolder.trim();
    await prefs.setString(keyInboxFolder, folder);
  }
}

/// In-memory store for tests.
class MemoryBotAgentSettingsStore implements BotAgentSettingsStore {
  MemoryBotAgentSettingsStore([this.value = const BotAgentSettings()]);

  BotAgentSettings value;

  @override
  Future<BotAgentSettings> read() async => value;

  @override
  Future<void> write(BotAgentSettings settings) async {
    value = settings;
  }
}
