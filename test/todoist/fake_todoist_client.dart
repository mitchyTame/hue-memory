import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:hue_memory/todoist/todoist_client.dart';

/// In-memory Todoist client that can be told to fail specific calls.
class ScriptedTodoistClient extends TodoistClient {
  ScriptedTodoistClient({List<TodoistTask> openTasks = const []})
      : open = List<TodoistTask>.from(openTasks),
        super(apiToken: 'test-token', httpClient: _UnusedHttp());

  final List<TodoistTask> open;
  final List<TodoistTask> created = [];
  final Map<String, String?> parentIds = {};
  final Map<String, int?> priorities = {};

  /// Task id → (due, has time) as sent on create.
  final Map<String, ({DateTime? due, bool hasTime})> dues = {};
  final List<String> closedIds = [];

  /// Task content → error thrown by [createInboxTask] while set.
  final Map<String, Object> createErrors = {};
  Object? listError;
  Object? labelError;
  final Set<String> closeErrors = {};

  /// Task ids that answer 404 (deleted / completed remotely) on close/update.
  final Set<String> closeNotFound = {};
  final Set<String> updateNotFound = {};

  /// Content → the create succeeds server-side but the response is lost.
  final Set<String> createThenTimeout = {};

  /// Runs just before each create is accepted (e.g. to inspect a store).
  Future<void> Function(String content)? beforeCreate;

  int listCalls = 0;

  /// Every X-Request-Id received by [createInboxTask], in order.
  final List<String?> requestIds = [];
  final Map<String, TodoistTask> _byRequestId = {};

  /// (task id, content, priority) per [updateTask] call.
  final List<({String id, String? content, int? priority})> updates = [];

  /// Task id → due sent by the latest [updateTask] that carried one.
  final Map<String, ({DateTime? due, bool hasTime})> updatedDues = {};

  @override
  Future<Map<String, TodoistLabel>> ensureLabels(Iterable<String> names) async {
    if (labelError != null) throw labelError!;
    return {for (final n in names) n: TodoistLabel(id: 'id-$n', name: n)};
  }

  @override
  Future<List<TodoistTask>> listOpenTasks() async {
    listCalls++;
    if (listError != null) throw listError!;
    return List.unmodifiable(open);
  }

  @override
  Future<TodoistTask> createInboxTask({
    required String content,
    List<String> labels = const [],
    int? priority,
    String? parentId,
    DateTime? dueDate,
    bool dueHasTime = false,
    String? description,
    String? requestId,
  }) async {
    requestIds.add(requestId);
    await beforeCreate?.call(content);
    final error = createErrors[content];
    if (error != null) throw error;
    final seen = requestId == null ? null : _byRequestId[requestId];
    if (seen != null) return seen;
    final task = TodoistTask(
      id: 'new-${created.length + 1}',
      content: content,
      labels: labels,
    );
    created.add(task);
    if (requestId != null) _byRequestId[requestId] = task;
    parentIds[task.id] = parentId;
    priorities[task.id] = priority;
    dues[task.id] = (due: dueDate, hasTime: dueHasTime);
    if (createThenTimeout.remove(content)) {
      throw TimeoutException('response lost');
    }
    return task;
  }

  @override
  Future<TodoistTask> updateTask(
    String taskId, {
    String? content,
    int? priority,
    String? description,
    DateTime? dueDate,
    bool dueHasTime = false,
  }) async {
    if (updateNotFound.contains(taskId)) {
      throw TodoistApiException('Todoist error 404', statusCode: 404);
    }
    updates.add((id: taskId, content: content, priority: priority));
    if (dueDate != null) {
      updatedDues[taskId] = (due: dueDate, hasTime: dueHasTime);
    }
    return TodoistTask(id: taskId, content: content ?? '');
  }

  @override
  Future<void> closeTask(String taskId) async {
    if (closeNotFound.contains(taskId)) {
      throw TodoistApiException('Todoist error 404', statusCode: 404);
    }
    if (closeErrors.contains(taskId)) {
      throw TodoistApiException('Todoist error 500', statusCode: 500);
    }
    closedIds.add(taskId);
    open.removeWhere((t) => t.id == taskId);
  }
}

class _UnusedHttp extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw StateError('Fake Todoist client must not hit the network');
  }
}
