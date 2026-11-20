import 'dart:convert';

import 'package:http/http.dart' as http;

/// Lightweight Todoist REST v2 client (Inbox tasks + personal labels).
class TodoistClient {
  TodoistClient({
    required this.apiToken,
    http.Client? httpClient,
    this.baseUrl = 'https://api.todoist.com/rest/v2',
  }) : _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null;

  final String apiToken;
  final String baseUrl;
  final http.Client _http;
  final bool _ownsHttp;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${apiToken.trim()}',
        'Content-Type': 'application/json',
      };

  void close() {
    if (_ownsHttp) _http.close();
  }

  Future<TodoistConnectionResult> verifyConnection() async {
    final token = apiToken.trim();
    if (token.isEmpty) {
      return const TodoistConnectionResult(
        ok: false,
        message: 'API token is empty',
      );
    }
    try {
      final res = await _http.get(
        Uri.parse('$baseUrl/labels'),
        headers: _headers,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return const TodoistConnectionResult(
          ok: true,
          message: 'Todoist connected',
        );
      }
      return TodoistConnectionResult(
        ok: false,
        message: _errorMessage(res.statusCode, res.body),
      );
    } catch (e) {
      return TodoistConnectionResult(ok: false, message: '$e');
    }
  }

  Future<List<TodoistLabel>> listLabels() async {
    final res = await _http.get(
      Uri.parse('$baseUrl/labels'),
      headers: _headers,
    );
    _ensureOk(res);
    final list = jsonDecode(res.body) as List<dynamic>;
    return list
        .map((e) => TodoistLabel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TodoistLabel> createLabel(String name) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/labels'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    _ensureOk(res);
    return TodoistLabel.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  /// Ensure each [names] label exists; returns name → id.
  Future<Map<String, String>> ensureLabels(Iterable<String> names) async {
    final existing = await listLabels();
    final byName = <String, String>{
      for (final l in existing) l.name.toLowerCase(): l.id,
    };
    final out = <String, String>{};
    for (final raw in names) {
      final name = raw.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      var id = byName[key];
      if (id == null) {
        final created = await createLabel(name);
        id = created.id;
        byName[key] = id;
      }
      out[name] = id;
    }
    return out;
  }

  Future<List<TodoistTask>> listOpenTasks() async {
    final res = await _http.get(
      Uri.parse('$baseUrl/tasks'),
      headers: _headers,
    );
    _ensureOk(res);
    final list = jsonDecode(res.body) as List<dynamic>;
    return list
        .map((e) => TodoistTask.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TodoistTask> createInboxTask({
    required String content,
    List<String> labels = const [],
    int? priority,
  }) async {
    final body = <String, dynamic>{
      'content': content,
      if (labels.isNotEmpty) 'labels': labels,
      'priority': ?priority,
    };
    final res = await _http.post(
      Uri.parse('$baseUrl/tasks'),
      headers: _headers,
      body: jsonEncode(body),
    );
    _ensureOk(res);
    return TodoistTask.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  Future<void> closeTask(String taskId) async {
    final res = await _http.post(
      Uri.parse('$baseUrl/tasks/$taskId/close'),
      headers: _headers,
    );
    if (res.statusCode != 204 &&
        (res.statusCode < 200 || res.statusCode >= 300)) {
      throw TodoistApiException(_errorMessage(res.statusCode, res.body));
    }
  }

  void _ensureOk(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw TodoistApiException(_errorMessage(res.statusCode, res.body));
    }
  }

  static String _errorMessage(int status, String body) {
    if (status == 401 || status == 403) {
      return 'Todoist token rejected ($status)';
    }
    final trimmed = body.trim();
    if (trimmed.isEmpty) return 'Todoist error $status';
    if (trimmed.length > 180) {
      return 'Todoist error $status: ${trimmed.substring(0, 180)}…';
    }
    return 'Todoist error $status: $trimmed';
  }
}

class TodoistConnectionResult {
  const TodoistConnectionResult({required this.ok, required this.message});

  final bool ok;
  final String message;
}

class TodoistLabel {
  const TodoistLabel({required this.id, required this.name});

  final String id;
  final String name;

  factory TodoistLabel.fromJson(Map<String, dynamic> json) {
    return TodoistLabel(
      id: '${json['id']}',
      name: '${json['name'] ?? ''}',
    );
  }
}

class TodoistTask {
  const TodoistTask({
    required this.id,
    required this.content,
    this.labels = const [],
  });

  final String id;
  final String content;
  final List<String> labels;

  factory TodoistTask.fromJson(Map<String, dynamic> json) {
    final rawLabels = json['labels'];
    final labels = <String>[];
    if (rawLabels is List) {
      for (final e in rawLabels) {
        labels.add('$e');
      }
    }
    return TodoistTask(
      id: '${json['id']}',
      content: '${json['content'] ?? ''}',
      labels: labels,
    );
  }
}

class TodoistApiException implements Exception {
  TodoistApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
