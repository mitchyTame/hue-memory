import 'package:shared_preferences/shared_preferences.dart';

import '../settings/secret_store.dart';

/// Todoist REST API token for · daily → Inbox sync.
class TodoistSettings {
  const TodoistSettings({
    this.apiToken = '',
  });

  final String apiToken;

  bool get hasToken => apiToken.trim().isNotEmpty;

  TodoistSettings copyWith({String? apiToken}) {
    return TodoistSettings(apiToken: apiToken ?? this.apiToken);
  }
}

abstract interface class TodoistSettingsStore {
  Future<TodoistSettings> read();
  Future<void> write(TodoistSettings settings);
}

class PrefsTodoistSettingsStore implements TodoistSettingsStore {
  PrefsTodoistSettingsStore({
    SharedPreferences? prefs,
    SecretStore? secrets,
    this.envApiToken = '',
  })  : _prefs = prefs,
        _secrets = secrets ?? FlutterSecretStore();

  static const keyApiToken = 'todoist_api_token';

  /// Optional process env / --dart-define override (never logged).
  final String envApiToken;
  SharedPreferences? _prefs;
  final SecretStore _secrets;

  Future<SharedPreferences> _ensure() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<TodoistSettings> read() async {
    final prefs = await _ensure();
    var stored = await _secrets.read(keyApiToken) ?? '';
    if (stored.isEmpty) {
      final legacy = prefs.getString(keyApiToken) ?? '';
      if (legacy.isNotEmpty) {
        await _secrets.write(keyApiToken, legacy);
        await prefs.remove(keyApiToken);
        stored = legacy;
      }
    }
    final token =
        envApiToken.trim().isNotEmpty ? envApiToken.trim() : stored;
    return TodoistSettings(apiToken: token);
  }

  @override
  Future<void> write(TodoistSettings settings) async {
    final prefs = await _ensure();
    final token = settings.apiToken.trim();
    if (token.isEmpty) {
      await _secrets.delete(keyApiToken);
    } else {
      await _secrets.write(keyApiToken, token);
    }
    await prefs.remove(keyApiToken);
  }
}

class MemoryTodoistSettingsStore implements TodoistSettingsStore {
  MemoryTodoistSettingsStore([this.value = const TodoistSettings()]);

  TodoistSettings value;

  @override
  Future<TodoistSettings> read() async => value;

  @override
  Future<void> write(TodoistSettings settings) async {
    value = settings;
  }
}
